# docker-mantisbt

This is a Docker image for Mantis Bug tracker (https://www.mantisbt.org/).

HOW TO RUN:
-----------

# Run MYSQL
docker run --tty -i -e MYSQL_ROOT_PASSWORD=<yourPASSWD> mysql

# Run MantisBT
docker run --tty -i --link $(docker ps | grep mysql | awk '{ print $1 }'):mysql -e MANTISBT_DB_PASSWORD=<yourPASSWD> mantisbt/1.3.4


