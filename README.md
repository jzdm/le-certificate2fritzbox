LE-Certificate2FRITZ!Box
===

Simple script to import a Let's Encrypt (or any other) certificate to a FRITZ!Box.

Inspired by https://www.synology-forum.de/threads/automatisierte-lets-encrypt-erneuerung-inkl-portfreigabe-fritz-box-integration.106559/post-860429

## Setup
Create a sufficiently authorized user on the FRITZ!Box.

Create the folder `cert` if not existent.

Copy file `credentials.sample` to `credentials` and insert username, password and the FRITZ!Box hostname into first, second and third line.

## Usage
Make sure to first copy the desired LE-certificate to the 'cert' subfolder.
The certificate files must be named as `cert.pem`, `fullchain.pem` and `privkey.pem`

Then call the script (periodically via cron)
```
./fbleup.sh
```

Optionally run as 

```
./fbleup.sh --checkCert
```

This will compare the expiration date of the local certificate file and the active certificate of the FRITZ!Box using `tlsCExp.sh`.
The certificate will only be updated if these dates are not the same.

The script could also be run with a privileged user able to read the certificate files at `/etc/letsencrypt/live/…`.
Update the the `CERTPATH` variable accordingly.

## Additional comments
The script was tested on FreeBSD only. It might also run under Linux.
When using `--checkCert` `tlsCExp.sh` probably needs some adjustements of the `date(1)` command.
