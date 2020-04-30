FROM terrestris/geoserver:2.16.2

# Customizable Variables
ENV GEOSERVER_URL "/geoserver"
ENV GEOSERVER_DATA_DIR /opt/geoserver/data_dir

COPY startup.sh /opt/startup.sh

ENTRYPOINT /opt/startup.sh

WORKDIR /opt
