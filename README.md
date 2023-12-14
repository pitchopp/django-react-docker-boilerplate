# django-react-docker-boilerplate
this tool makes it easy to start a clean dockerized django-react in 1 command

## Get started

You can use the following command to start a project name "myproject"

```bash
sh init.sh myproject
```

then it will create all necessary files for django and react and also docker files.

you gonna need to set at least a django secret key in the prod.env file located at the root of the project (not the django folder)

```bash
# ./prod.env

DJANGO_SECRET_KEY=
DOMAIN_NAME=localhost
REACT_APP_API_URL=http://api.localhost
```

you are ready to launch the app

```bash
# to run in local mode
sh run.sh dev

# to run in production mode
sh run.sh prod
```

in any case you can now access your web app here : [http://localhost](http://localhost)

your django admin panel is located here [http://admin.localhost](http://admin.localhost)

you also have a default subdomain for your apis here [http://api.localhost](http://api.localhost) but for the moment it doesn't contain any view (in dev mode you can still see django's default view)

good hacking !
