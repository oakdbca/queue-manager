# Prepare the base environment.
FROM ubuntu:22.04 as builder_base_parkstay
MAINTAINER asi@dbca.wa.gov.au
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Australia/Perth
ENV PRODUCTION_EMAIL=True
ENV SECRET_KEY="ThisisNotRealKey"
RUN apt-get clean
RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get install --no-install-recommends -y wget git libmagic-dev gcc binutils libproj-dev gdal-bin python3 python3-setuptools python3-dev python3-pip tzdata libreoffice cron rsyslog gunicorn
RUN apt-get install --no-install-recommends -y libpq-dev patch
RUN apt-get install --no-install-recommends -y postgresql-client mtr
RUN apt-get install --no-install-recommends -y sqlite3 vim postgresql-client ssh htop
RUN ln -s /usr/bin/python3 /usr/bin/python 
RUN pip install --upgrade pip
RUN wget -O /tmp/GDAL-3.8.3-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl https://github.com/girder/large_image_wheels/raw/wheelhouse/GDAL-3.8.3-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl#sha256=e2fe6cfbab02d535bc52c77cdbe1e860304347f16d30a4708dc342a231412c57
RUN pip install /tmp/GDAL-3.8.3-cp310-cp310-manylinux_2_17_x86_64.manylinux2014_x86_64.whl

# Install Python libs from requirements.txt.
FROM builder_base_parkstay as python_libs_parkstay
WORKDIR /app
COPY requirements.txt ./
RUN pip3 install --no-cache-dir -r requirements.txt \
  # Update the Django <1.11 bug in django/contrib/gis/geos/libgeos.py
  # Reference: https://stackoverflow.com/questions/18643998/geodjango-geosexception-error
  #&& sed -i -e "s/ver = geos_version().decode()/ver = geos_version().decode().split(' ')[0]/" /usr/local/lib/python3.6/dist-packages/django/contrib/gis/geos/libgeos.py \
  && rm -rf /var/lib/{apt,dpkg,cache,log}/ /tmp/* /var/tmp/*

# Install the project (ensure that frontend projects have been built prior to this step).
FROM python_libs_parkstay
COPY timezone /etc/timezone
ENV TZ=Australia/Perth
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

#COPY libgeos.py.patch /app/
#RUN patch /usr/local/lib/python3.8/dist-packages/django/contrib/gis/geos/libgeos.py /app/libgeos.py.patch
#RUN rm /app/libgeos.py.patch

COPY cron /etc/cron.d/dockercron
COPY startup.sh /
#RUN service rsyslog start
RUN chmod 0644 /etc/cron.d/dockercron
RUN crontab /etc/cron.d/dockercron
RUN touch /var/log/cron.log
RUN service cron start
RUN chmod 755 /startup.sh
COPY gunicorn.ini manage.py ./
#COPY ledger ./ledger
RUN touch /app/.env
COPY queuemanager ./queuemanager
COPY django_site_queue ./django_site_queue
#COPY .git/refs/heads/master /app/git_hash
RUN mkdir /app/queuemanager/cache/
RUN chmod 777 /app/queuemanager/cache/
RUN python manage.py collectstatic --noinput
EXPOSE 8080
HEALTHCHECK --interval=1m --timeout=5s --start-period=10s --retries=3 CMD ["wget", "-q", "-O", "-", "http://localhost:8080/"]
CMD ["/startup.sh"]
#CMD ["gunicorn", "parkstay.wsgi", "--bind", ":8080", "--config", "gunicorn.ini"]

