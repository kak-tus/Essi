# Essi - automated perl to deb converter

Essi based on [dh-make-perl](https://metacpan.org/pod/DhMakePerl).

Essi is a web service with HTTP api (github/gitlab/custom webhooks notification suport) that get some notification with repo name, download it and creates deb package.

Essi is a part of CI.

## Installation

Best way to use Essi - docker image [kaktuss/essi](https://hub.docker.com/r/kaktuss/essi/).

If you want to start it in usual environment - you must install it

```
cpanm -S https://github.com/kak-tus/Essi.git
```

and start it

```
sudo hypnotoad /usr/local/bin/essi.pl
```

## Github/gitlab API

```
http://example-domain:9007/v1/build/github.json
```

or

```
http://example-domain:9007/v1/build/gitlab.json
```

But the better solution in non-private environment: use nginx (+https) and proxy pass to application like

```
https://example-domain/essi/
```

to

```
http://127.0.0.1:9007/
```

## Custom API

POST request

```
http://example-domain:9007/v1/build/custom.json
```

with parameter

```
repo=https://github.com/kak-tus/Essi.git
```

Curl example

```
curl -X POST 'http://example-domain:9007/v1/build/custom.json?repo=https://github.com/kak-tus/Essi.git'
```

## File API

Allow to download tar.gz file from cpan (or any other storage) and build it.

POST request

```
http://example-domain:9007/v1/build/file.json
```

with parameter

```
url=https://cpan.metacpan.org/authors/id/K/KA/KAKTUS/Geo-SypexGeo-0.6.tar.gz
```

Curl example

```
curl -X POST 'http://example-domain:9007/v1/build/file.json?url=https://cpan.metacpan.org/authors/id/K/KA/KAKTUS/Geo-SypexGeo-0.6.tar.gz'
```
