
log "getting postgresql_pw"

POSTGRESQL_PW=${POSTGRESQL_PW:-$(mdata-get postgresql_pw 2>/dev/null)} || \
POSTGRESQL_PW=$(od -An -N8 -x /dev/random | head -1 | tr -d ' ');

log "starting the PostgreSQL instance"
svcadm enable -r svc:/pkgsrc/postgresql:default

log "waiting for the socket to show up"
COUNT="0";
while [[ ! -e /var/pgsql/data/postmaster.pid ]]; do
        sleep 1
        ((COUNT=COUNT+1))
        if [[ $COUNT -eq 60 ]]; then
          log "ERROR Could not talk to PostgreSQL after 60 seconds"
    ERROR=yes
    break 1
  fi
done
[[ -n "${ERROR}" ]] && exit 31
log "(it took ${COUNT} seconds to start properly)"

sleep 1

[[ "$(svcs -Ho state postgresql)" == "online" ]] || \
  ( log "ERROR PostgreSQL SMF not reporting as 'online'" && exit 31 )

log "running the access lockdown SQL query"

sudo PGPASSWORD=postgres psql -U postgres -w -d template1 -c "ALTER USER gitlab WITH PASSWORD '${POSTGRESQL_PW}'" >/dev/null || \
  ( log "ERROR PostgreSQL query failed to execute." && exit 31 ) 

log "configuring redis to bind to localhost only"
gsed -i \
        -e "s/# bind 127.0.0.1/bind 127.0.0.1/" \
        -e "s/# unixsocket \/tmp\/redis.sock/unixsocket \/tmp\/redis.sock/" \
        /opt/local/etc/redis.conf

log "starting the redis instance"
svcadm enable redis

log "waiting for the socket to show up"
COUNT="0";
while [[ ! -e /tmp/redis.sock ]]; do
        sleep 1
        ((COUNT=COUNT+1))
        if [[ $COUNT -eq 60 ]]; then
          log "ERROR Could not talk to redis after 60 seconds"
    ERROR=yes
    break 1
  fi
done
[[ -n "${ERROR}" ]] && exit 31
log "(it took ${COUNT} seconds to start properly)"

sleep 1

[[ "$(svcs -Ho state redis)" == "online" ]] || \
  ( log "ERROR redis SMF not reporting as 'online'" && exit 31 )

log "configuring git"
sudo -u git -H git config --global user.name "GitLab"
sudo -u git -H git config --global user.email "gitlab@localhost"
sudo -u git -H git config --global core.autocrlf input

log "configuring gitlab-shell"
cd /home/git/gitlab-shell

log "getting gitlab_root_pw"

GITLAB_ROOT_PW=${GITLAB_ROOT_PW:-$(mdata-get gitlab_root_pw 2>/dev/null)} || \
GITLAB_ROOT_PW="5iveL!fe";

log "configuring gitlab"
cd /home/git/gitlab
gsed -i \
        -e "s/%POSTGRESQL_PW%/${POSTGRESQL_PW}/" \
        /home/git/gitlab/config/database.yml
gsed -i \
        -e "s/%HOSTNAME%/${HOSTNAME}/" \
        /home/git/gitlab/config/gitlab.yml
gsed -i \
        -e "s/%HOSTNAME%/${HOSTNAME}/" \
        /opt/local/etc/nginx/nginx.conf
sudo -u git -H bundle exec rake gitlab:setup RAILS_ENV=production GITLAB_ROOT_PASSWORD="${GITLAB_ROOT_PW}" force=yes

log "starting the postfix instance"
svcadm enable postfix

log "starting the gitlab-sidekiq instance"
svcadm enable gitlab-sidekiq

log "starting the gitlab instance"
svcadm enable gitlab

log "starting the nginx instance"
svcadm enable nginx
