#!/bin/sh
set -eu

: "${MONGO_ROOT_USERNAME:?MONGO_ROOT_USERNAME is required}"
: "${MONGO_ROOT_PASSWORD:?MONGO_ROOT_PASSWORD is required}"
: "${MONGO_APP_USERNAME:?MONGO_APP_USERNAME is required}"
: "${MONGO_APP_PASSWORD:?MONGO_APP_PASSWORD is required}"
: "${MONGODB_DATABASE:?MONGODB_DATABASE is required}"
: "${MONGODB_REPLICA_MEMBER_HOST:?MONGODB_REPLICA_MEMBER_HOST is required}"

mongo_command() {
  mongosh --host mongodb:27017 --quiet \
    --username "$MONGO_ROOT_USERNAME" \
    --password "$MONGO_ROOT_PASSWORD" \
    --authenticationDatabase admin "$@"
}

until mongo_command --eval 'db.adminCommand({ ping: 1 }).ok' | grep -qx '1'; do
  sleep 2
done

mongo_command --eval '
const replicaMemberHost = process.env.MONGODB_REPLICA_MEMBER_HOST;
const replicaSet = {_id: "rs0", members: [{_id: 0, host: replicaMemberHost}]};
try {
  rs.status();
} catch (error) {
  rs.initiate(replicaSet);
}

function waitForPrimary() {
  const deadline = Date.now() + 60000;
  while (!db.hello().isWritablePrimary) {
    if (Date.now() > deadline) {
      throw new Error("MongoDB did not become primary within 60 seconds");
    }
    sleep(1000);
  }
}

waitForPrimary();

const currentConfiguration = rs.conf();
if (currentConfiguration.members.length !== 1 || currentConfiguration.members[0].host !== replicaMemberHost) {
  currentConfiguration.members = [{_id: 0, host: replicaMemberHost}];
  currentConfiguration.version += 1;
  rs.reconfig(currentConfiguration);
  waitForPrimary();
}

const applicationDatabase = db.getSiblingDB(process.env.MONGODB_DATABASE);
const applicationUser = process.env.MONGO_APP_USERNAME;
const applicationPassword = process.env.MONGO_APP_PASSWORD;
const applicationRoles = [{role: "readWrite", db: process.env.MONGODB_DATABASE}];

if (applicationDatabase.getUser(applicationUser)) {
  applicationDatabase.updateUser(applicationUser, {
    pwd: applicationPassword,
    roles: applicationRoles
  });
} else {
  applicationDatabase.createUser({
    user: applicationUser,
    pwd: applicationPassword,
    roles: applicationRoles
  });
}
'
