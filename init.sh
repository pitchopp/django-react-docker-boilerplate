if [ -z "$1" ]; then
    echo "No argument supplied"
    exit 1
fi

# if backend-django folder doesn't exist, create it
if [ ! -d "backend-django" ]; then
    mkdir backend-django
fi

cd backend-django

# init poetry
poetry init --no-interaction --python ">=3.10"

# remove packages line from pyproject.toml
FILE=pyproject.toml

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS uses an empty string with -i
    sed -i '' '/^packages =/d' "$FILE"
else
    # Linux and other Unix-like systems
    sed -i '/^packages =/d' "$FILE"
fi

poetry add django djangorestframework django-cors-headers python-decouple django-hosts
poetry add --group prod psycopg2-binary gunicorn

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS uses an empty string with -i
    sed -i '' "/\[tool.poetry.group.prod.dependencies\]/i \\
\[tool.poetry.group.prod\]\\
optional = true\\

" "$FILE"
else
    # Linux and other Unix-like systems
    sed -i "/\[tool.poetry.group.prod.dependencies\]/i \\
\[tool.poetry.group.prod\]\\
optional = true\\

" "$FILE"
fi

poetry lock

poetry run django-admin startproject $1 .
poetry run django-admin startapp api

echo "from django.contrib import admin
from django.urls import path

urlpatterns = [
]" > api/urls.py

echo "from django.contrib import admin
from django.urls import path

urlpatterns = [
    path('', admin.site.urls),
]" > $1/admin_urls.py

echo "from django_hosts import patterns, host
from django.conf import settings

host_patterns = patterns('',
    host(r'', settings.ROOT_URLCONF, name=' '),
    host(r'api', 'api.urls', name='api'),
    host(r'admin', '$1.admin_urls', name='admin')
)" > $1/hosts.py

echo "from django.contrib import admin
from django.urls import path

urlpatterns = [
]" > $1/urls.py

FILE="$1/settings.py"

function sed_inplace() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "$@" "$FILE"
    else
        # Linux and other Unix-like systems
        sed -i "$@" "$FILE"
    fi
}

sed_inplace "/from pathlib import Path/i \\
from decouple import config
"
sed_inplace "s/^SECRET_KEY =.*/SECRET_KEY = config('DJANGO_SECRET_KEY')/"
sed_inplace "s/^DEBUG =.*/DEBUG = config('DJANGO_DEBUG', cast=bool, default=False)/"
sed_inplace "/ALLOWED_HOSTS/i \\
_DOMAIN_NAME = config('DOMAIN_NAME', 'localhost')
"
sed_inplace "s/^ALLOWED_HOSTS =.*/ALLOWED_HOSTS = \[f'api.{_DOMAIN_NAME}', f'admin.{_DOMAIN_NAME}'\]\\
DEFAULT_HOST = config('DEFAULT_HOST', default=' ')\\
ROOT_HOSTCONF = '$1.hosts'/
"
sed_inplace "/INSTALLED_APPS = \[/,/\]/ { /\]/i \\
    'django_hosts',\\
    'rest_framework',\\
    'api',\\
\]
/]/d; }"
sed_inplace "s/^MIDDLEWARE =.*/MIDDLEWARE = \[\\
    # HostsRequestMiddleware must be the first middleware in the list\\
    'django_hosts.middleware.HostsRequestMiddleware',\\
    # ---------------------------------------------------------------/
"
sed_inplace "/MIDDLEWARE = \[/,/\]/ { /\]/i \\
    # HostsResponseMiddleware must be the last middleware in the list\\
    'django_hosts.middleware.HostsResponseMiddleware',\\
    # ---------------------------------------------------------------\\
\]
/]/d; }"
sed_inplace "s/^        'ENGINE': 'django.db.backends.sqlite.*/        'ENGINE': config('DB_ENGINE', default='django.db.backends.sqlite3'),/"
sed_inplace "s/^        'NAME': BASE_DIR.*/        'NAME': config('DB_NAME', default='db.sqlite3'),\\
        'USER': config('DB_USER', default=''),\\
        'PASSWORD': config('DB_PASSWORD', default=''),\\
        'HOST': config('DB_HOST', default=''),\\
        'PORT': config('DB_PORT', default=''),/
"
sed_inplace "s/^STATIC_URL =.*/STATIC_URL = 'static\/'\\
STATIC_ROOT = BASE_DIR \/ 'static'\\
\\
MEDIA_URL = 'media\/'\\
MEDIA_ROOT = BASE_DIR \/ 'media'/
"

echo "# The base image we want to inherit from
FROM python:3.11-alpine

ENV PYTHONFAULTHANDLER=1 \\
  PYTHONUNBUFFERED=1 \\
  PYTHONHASHSEED=random \\
  # pip:
  PIP_NO_CACHE_DIR=off \\
  PIP_DISABLE_PIP_VERSION_CHECK=on \\
  PIP_DEFAULT_TIMEOUT=100 \\
  # poetry:
  POETRY_VERSION=1.5.1 \\
  POETRY_VIRTUALENVS_CREATE=true \\
  POETRY_CACHE_DIR='/var/cache/pypoetry'

# Update and install necessary packages using apk
RUN apk update && \\
    apk add --no-cache bash build-base curl gettext git libpq-dev wget libffi-dev && \\
    rm -rf /var/cache/apk/* && \\
    pip3 install --upgrade pip setuptools wheel && \\
    pip3 install \"poetry==\${POETRY_VERSION}\" && \\
    poetry --version && \\
    poetry config virtualenvs.in-project false

# set work directory
WORKDIR /code

COPY pyproject.toml /code/

RUN poetry install --with prod

COPY . ." > Dockerfile

echo ".venv
Dockerfile
.gitignore
.git
.dockerignore" > .dockerignore

echo "poetry run python manage.py migrate
poetry run python manage.py runserver 0.0.0.0:8000" > entrypoint.dev.sh

echo "#!/bin/sh

if [ \"\$DATABASE\" = \"postgres\" ]
then
    echo 'Waiting for postgres...'

    while ! nc -z \$DB_HOST \$DB_PORT; do
      sleep 0.1
    done

    echo 'PostgreSQL started'
fi

poetry run python manage.py migrate
poetry run python manage.py collectstatic --noinput
poetry run gunicorn $1.wsgi:application --bind 0.0.0.0:8000" > entrypoint.prod.sh

cd ..

npx create-react-app webapp-react

echo "FROM node:21.2.0-alpine

WORKDIR /code

COPY package*.json ./

RUN npm install

COPY . ." > webapp-react/Dockerfile

# create docker folder if it doesn't exist
if [ ! -d "docker" ]; then
    mkdir docker
fi

cd docker

# create nginx folder if it doesn't exist
if [ ! -d "nginx" ]; then
    mkdir nginx
fi

echo "FROM nginx:1.25-alpine

ARG ENV

ENV conf_file=nginx.conf.\${ENV}.template

RUN rm /etc/nginx/conf.d/default.conf
RUN echo \"conf_file: \$conf_file\"
COPY \${conf_file} /\${conf_file}

CMD [\"/bin/sh\" , \"-c\" , \"envsubst '\$DOMAIN_NAME' < /\${conf_file} > /etc/nginx/conf.d/nginx.conf && exec nginx -g 'daemon off;'\"]" > nginx/Dockerfile

echo "upstream back {
    server backend-django:8000;
}

upstream front {
    server frontend-react:3000;
}

server {
    server_name api.\$DOMAIN_NAME admin.\$DOMAIN_NAME;

    location / {
        proxy_pass http://back;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Host \$host;
        proxy_redirect off;
    }

}

server {
    server_name \$DOMAIN_NAME www.\$DOMAIN_NAME;

    location / {
        proxy_pass http://front;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Host \$host;
        proxy_redirect off;
    }
}" > nginx/nginx.conf.dev.template

echo "upstream back {
    server backend-django:8000;
}

server {
    server_name api.\$DOMAIN_NAME admin.\$DOMAIN_NAME;

    location / {
        proxy_pass http://back;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Host \$host;
        proxy_redirect off;
    }
    
    location /static/ {
        alias /var/www/static/;
    }

    location /media/ {
        alias /var/www/media/;
    }

}

server {
    server_name \$DOMAIN_NAME www.\$DOMAIN_NAME;

    root /var/www/webapp;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
}" > nginx/nginx.conf.prod.template

echo "services:
  frontend-react:
    build: 
      context: ../webapp-react
      dockerfile: Dockerfile
    depends_on:
      - backend-django
  
  backend-django: 
    build: 
      context: ../backend-django
      dockerfile: Dockerfile
    expose:
      - "8000"
  
  db:
    image: postgres:15-alpine
    expose:
      - 5432
    environment:
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_USER=postgres
      - POSTGRES_DB=postgres
  
  nginx:
    build: 
      context: ./nginx
      dockerfile: Dockerfile
    ports:
      - 80:80
    environment:
      - DOMAIN_NAME=localhost
    depends_on:
      - backend-django" > compose.base.yml

echo "services:
  frontend-react:
    extends:
      file: compose.base.yml
      service: frontend-react
    command: ['npm', 'start']
    volumes:
      - ../webapp-react:/code
    environment:
      - REACT_APP_API_URL=http://api.localhost
    env_file:
      - ../dev.env
  
  backend-django:
    extends:
      file: compose.base.yml
      service: backend-django
    entrypoint: ['sh', '/code/entrypoint.dev.sh']
    volumes:
      - ../backend-django:/code
    environment:
      - DJANGO_DEBUG=True
      - DJANGO_SECRET_KEY='django-insecure-n+nd9(o40^i5pxbe(qtsh3@vcpvw_fbb701g)de8^j=@3nj+5='
    env_file:
      - ../dev.env
  nginx:
    extends:
      file: compose.base.yml
      service: nginx
    build:
      args:
        ENV: dev" > compose.dev.yml

echo "services:  
  frontend-react:
    extends:
      file: compose.base.yml
      service: frontend-react
    entrypoint: ['npm', 'run', 'build']
    volumes:
      - webapp_volume:/code/build
    env_file:
      - ../prod.env
  
  backend-django:
    extends:
      file: ./compose.base.yml
      service: backend-django
    entrypoint: ['sh', '/code/entrypoint.prod.sh']
    volumes:
      - static_volume:/code/static
      - media_volume:/code/media
    environment:
      - DJANGO_DEBUG=False
      - DATABASE=postgres
      - DB_ENGINE=django.db.backends.postgresql
      - DB_NAME=postgres
      - DB_USER=postgres
      - DB_PASSWORD=postgres
      - DB_HOST=db
      - DB_PORT=5432
    env_file:
      - ../prod.env
    depends_on:
      - db
  
  db:
    extends:
      file: ./compose.base.yml
      service: db
    volumes:
      - postgres_data:/var/lib/postgresql/data/
  
  nginx:
    extends:
      file: ./compose.base.yml
      service: nginx
    volumes:
      - static_volume:/var/www/static
      - media_volume:/var/www/media
      - webapp_volume:/var/www/webapp
    build:
      args:
        ENV: prod
    env_file:
      - ../prod.env

volumes:
  postgres_data:
    name: $1-postgres
  static_volume:
    name: $1-static
  media_volume:
    name: $1-media
  webapp_volume:
    name: $1-webapp" > compose.prod.yml

cd ..

echo "# Check if docker is installed
if ! [ -x \"\$(command -v docker)\" ]; then
  echo \"Error: docker is not installed.\" >&2
  exit 1
fi

# Check if docker-compose is installed
if ! [ -x \"\$(command -v docker-compose)\" ]; then
  echo \"Error: docker-compose is not installed.\" >&2
  exit 1
fi

# read input param
if [ -z \"\$1\" ]; then
    echo \"No argument supplied\"
    exit 1
fi

# check if input param is valid
if [ \"\$1\" != \"dev\" ] && [ \"\$1\" != \"prod\" ]; then
    echo \"Invalid argument supplied. Valid arguments are dev or prod\"
    exit 1
fi

# check if docker-compose file exists for input param (docker-compose.dev.yml, docker-compose.prod.yml)
if [ ! -f \"./docker/compose.\$1.yml\" ]; then
    echo \"compose.\$1.yml file not found!\"
    exit 1
fi

docker compose -f ./docker/compose.\$1.yml -p $1-\$1 up -d --build" > run.sh

echo "" > dev.env

echo "DOMAIN_NAME=localhost
REACT_APP_API_URL=http://api.localhost" > prod.env

echo "*.env" >> .gitignore
