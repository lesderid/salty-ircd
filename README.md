# salty-ircd
salty-ircd is an [Internet Relay Chat](https://en.wikipedia.org/wiki/Internet_Relay_Chat) daemon written in [D](https://dlang.org/).

## Goals
The main goals of salty-ircd are strict RFC compliance and security.

### RFC compliance
salty-ircd aims to be fully compliant with the IRC RFCs (in 'RFC mode'), specifically [RFC 1459](https://tools.ietf.org/html/rfc1459), [RFC 2811](https://tools.ietf.org/html/rfc2811), [RFC 2812](https://tools.ietf.org/html/rfc2812), and [RFC 2813](https://tools.ietf.org/html/rfc2813) (planned), including all errata.
Newer RFCs take precedence over older RFCs.

Any additional features breaking RFC compliance are available through compile-time options.

### Security
The following rules apply when any compile-time option is enabled (breaking strict RFC compliance):

* TLS is required for all connections, except connections from localhost (useful for running a Tor hidden service, which already has encryption)
* TLS client certificates are required for oper and vhost authentication

## Building
Build dependencies:
* A D compiler
* dub
* fish
* git

Build command:
* RFC compliant: `dub build`
* With all additional features: `dub build -c=modern`

TODO: Add a way to supply a custom list of compile-time options.

## Running
First, create the configuration file, `config.sdl`. You can find a template in `config.template.sdl`.

Then, simply run `./out/salty-ircd`.

## License
The source code for salty-ircd is licensed under the [University of Illinois/NCSA Open Source License](LICENSE).
