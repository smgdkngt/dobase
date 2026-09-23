# Deploying on Railway

[Railway](https://railway.com) runs Dobase from this repository's Dockerfile, with
`railway.json` for the build and deploy settings. It's the quickest way to a hosted
Dobase without a server of your own; Railway bills by use.

## One service, one volume

Dobase keeps everything, database included, in `/rails/storage` (SQLite). On Railway:

| Setting | Value | Why |
|---------|-------|-----|
| Volume | mounted at `/rails/storage` | The database, uploaded files and the secret key live here |
| Replicas | 1 | SQLite is one file; `railway.json` pins this |
| Public networking | a Railway domain (or yours), target port **80** | Thruster listens on 80 and hands requests to Rails |

## Variables

| Variable | Value | Why |
|----------|-------|-----|
| `RAILWAY_RUN_UID` | `0` | Railway mounts volumes owned by root; the image runs as a non-root user, which couldn't write to it otherwise |
| `SOLID_QUEUE_IN_PUMA` | `true` | Runs background jobs (mail sync, notifications) in the web process |
| `APP_HOST` | `${{RAILWAY_PUBLIC_DOMAIN}}` | Links in emails |
| `PORT` | `3000` | Where Rails listens behind Thruster |
| `SECRET_KEY_BASE` | `${{secret(64)}}` | Optional: without it Dobase makes one and keeps it in the volume |

Email (`SMTP_*`) and video rooms (`LIVEKIT_*`) are optional, as anywhere; see the
README's configuration section.

The first person to open the app signs up and becomes its first user. After that,
sign-up is by invitation unless `OPEN_REGISTRATION=true`.

## The template

A Railway template bundles the service, volume and variables above behind a
"Deploy on Railway" button. To make one: in Railway, deploy this repository as a
service with the settings above, check it runs, then choose **Create template** from
the project and publish it. The template's URL gives the button:

```markdown
[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/<template-code>)
```
