FROM nginx:1.18

COPY default.conf /etc/nginx/conf.d/default.conf

RUN mkdir -p /usr/share/nginx/html && \
    chown -R www-data:www-data /usr/share/nginx/html

EXPOSE 80
