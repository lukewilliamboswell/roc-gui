import Host
import InternalHttp
import Resource
import http.Request
import http.Response

Http := [].{

	## Opaque authority to reach exactly the granted origin.
	Client := Resource.HttpClient.{

		## Send a canonical roc-lang/http request under explicit finite limits.
		send! : Client, Config, Request => Try(Response, HttpErr)
		send! = |Client.(client), Config.(config), request| Host.http_send!(InternalHttp.to_host(client, request, config)).map_ok(InternalHttp.from_host).map_err(|reason| SendHttpErr(reason))
	}
	Reason : [AccessDenied, BodyTooLarge, ConnectFailed, InvalidCapability, InvalidHeader, InvalidRequest, InvalidUrl, RedirectLimit, Revoked, Timeout, UnsupportedScheme]
	HttpErr : [AcquireHttpErr(Reason), SendHttpErr(Reason)]

	## The finite limits one exchange runs under. Every field has a default, so
	## a caller states only the limits it actually wants to move.
	Config := {
		timeout_ms : U64 ?? 30_000,
		max_response_bytes : U64 ?? 1024 * 1024,
		max_redirects : U8 ?? 3,
	}

	## Acquire the network authority explicitly granted by `--host-cap-http-origin`.
	acquire! : Resource.Access => Try(Client, HttpErr)
	acquire! = |_access| Host.http_acquire!().map_ok(|resource| Client.(resource)).map_err(|reason| AcquireHttpErr(reason))
}
