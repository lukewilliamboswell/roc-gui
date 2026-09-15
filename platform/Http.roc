import Host
import InternalHttp
import Resource
import http.Request
import http.Response

Http := [].{
	Client :: Resource.HttpClient
	Error : [AccessDenied, BodyTooLarge, ConnectFailed, InvalidCapability, InvalidHeader, InvalidRequest, InvalidUrl, RedirectLimit, Timeout, UnsupportedScheme]
	Config : { timeout_ms : U64, max_response_bytes : U64, max_redirects : U8 }
	default_config : Config
	default_config = { timeout_ms: 30_000, max_response_bytes: 1024 * 1024, max_redirects: 3 }

	## Acquire the network authority explicitly granted by `--host-cap-http-origin`.
	acquire! : {} => Try(Client, Error)
	acquire! = |_| Host.http_acquire!({}).map_ok(|resource| Client.(resource))

	## Send a canonical roc-lang/http request under explicit finite limits.
	send! : Client, Config, Request => Try(Response, Error)
	send! = |Client.(client), config, request| Host.http_send!(InternalHttp.to_host(client, request, config)).map_ok(InternalHttp.from_host)
}
