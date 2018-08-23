#!/bin/bash

ACCESS_KEY=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20 ; echo '')
SECRET_KEY=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 20 ; echo '')

read -p "Enter a domain name: " DOMAIN
read -p "Enter an email address: " EMAIL
read -p "Choose an access key (random key): " -e -i $ACCESS_KEY ACCESS_KEY
read -p "Choose a secret key (random key): " -e -i $SECRET_KEY SECRET_KEY

echo -e "\n"

function get_certs() {
    certbot certonly --standalone -d $DOMAIN --staple-ocsp \
    -m $EMAIL --agree-tos

    cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /mnt/config/certs/public.crt
    cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /mnt/config/certs/private.key

    docker restart minio1
}

function install_minio_no_ssl() {
    apt-get update
    echo "Just a sec..."
    sleep 5
    apt-get install moreutils docker.io jq

    docker run -p 9000:9000 --name minio1 --restart=always -d \
    -e "MINIO_ACCESS_KEY="$ACCESS_KEY \
    -e "MINIO_SECRET_KEY="$SECRET_KEY \
    -v /mnt/data:/data \
    -v /mnt/config:/root/.minio \
    minio/minio server /data

    echo "Just a sec..."
    sleep 5

    # jq '.domain = "$DOMAIN"' /mnt/config/config.json|sponge /mnt/config/config.json
    tmp=$(mktemp)
    jq --arg domain "$DOMAIN" '.domain = $domain' /mnt/config/config.json > "$tmp" && mv "$tmp" /mnt/config/config.json

    echo -e "\nYou may now login at http://$DOMAIN:9000 \n"
    echo "ACCESS_KEY: "$ACCESS_KEY
    echo "SECRET_KEY: "$SECRET_KEY
    echo -e "\n"

}

function install_minio() {
    apt-get update
    apt-get install software-properties-common
    add-apt-repository ppa:certbot/certbot
    apt-get update
    apt-get install docker.io certbot

    mkdir -p /mnt/config/certs
    get_certs
    # set crontab to automatically renew letsencrypt certs
    (crontab -l ; echo "1 4 * * * certbot renew --agree-tos --deploy-hook /root/minio_cert_renewal.sh ") | crontab -

    # make cert renewal deploy-hook script
    echo "#!/bin/bash
cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /mnt/config/certs/public.crt
cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /mnt/config/certs/private.key
docker restart minio1" > /root/minio_cert_renewal.sh

    chmod +x /root/minio_cert_renewal.sh

    docker run -p 443:443 --name minio1 --restart=always -d \
    -e "MINIO_ACCESS_KEY="$ACCESS_KEY \
    -e "MINIO_SECRET_KEY="$SECRET_KEY \
    -v /mnt/data:/data \
    -v /mnt/config:/root/.minio \
    minio/minio server --address ":443" /data

    echo -e "\nYou may now login at https://$DOMAIN with the following credentials\n\n"

    echo "ACCESS_KEY: "$ACCESS_KEY
    echo "SECRET_KEY: "$SECRET_KEY
    echo -e "\n\n"

    echo -e "If you cannot access the site, \
the most probably cause is your dns hasnt fully propogated yet and letsencrypt was unable to retrieve a certificate. \
run the script later and choose option 2 to try to get an ssl cert again\n"
    

}




PS3='Please enter your choice: '
options=("Install Minio and retrieve ssl cert from letsencrypt" "Install Minio with no ssl" "Attempt to retrieve ssl cert again" "Quit")
select opt in "${options[@]}"
do
    case $opt in
        "Install Minio and retrieve ssl cert from letsencrypt")
            install_minio
            break
            ;;
        "Install Minio with no ssl")
            install_minio_no_ssl
            break
            ;;
        "Attempt to retrieve ssl cert again")
            get_certs
            break
            ;;
        "Quit")
            break
            ;;
        *) echo invalid option;;
    esac
done