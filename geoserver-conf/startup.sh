#!/bin/sh

# Updating geoserver path
sed "155c<Context path=\"${GEOSERVER_URL}\" docBase=\"${CATALINA_HOME}/webapps/geoserver/\"/>" /usr/local/tomcat/conf/server.xml > /root/server.xml
mv /root/server.xml /usr/local/tomcat/conf/server.xml

ADDITIONAL_LIBS_DIR=/opt/additional_libs/

# copy additional geoserver libs before starting the tomcat
if [ -d "${ADDITIONAL_LIBS_DIR}" ]; then
    cp ${ADDITIONAL_LIBS_DIR}/*.jar ${CATALINA_HOME}/webapps/geoserver/WEB-INF/lib/
fi

# start the tomcat
${CATALINA_HOME}/bin/catalina.sh run
