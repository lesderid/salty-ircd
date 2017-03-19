# salty-ircd

salty-ircd is an [Internet Relay Chat](https://en.wikipedia.org/wiki/Internet_Relay_Chat) daemon written in [D](https://dlang.org/).

## Goals
The main goals of salty-ircd are strict RFC compliance and security.

### RFC compliance
salty-ircd aims to be fully compliant with the IRC RFCs, specifically [RFC 1459](https://tools.ietf.org/html/rfc1459), [RFC 2811](https://tools.ietf.org/html/rfc2811), [RFC 2811](https://tools.ietf.org/html/rfc2812), and [RFC 2813](https://tools.ietf.org/html/rfc2813) (planned).  
Newer RFCs take precedence over older RFCs.

Any additional features breaking RFC compliance will be made available through compile-time options.

### Security
 * salty-ircd will require TLS for all connections. An exception could be made to allow hosting a Tor hidden service.
 * salty-ircd will require TLS client certificates for authentication.

## License
The source code for salty-ircd is licensed under the [University of Illinois/NCSA Open Source License](LICENSE).
