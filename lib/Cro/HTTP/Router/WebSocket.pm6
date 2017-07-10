use Base64;
use Digest::SHA1::Native;
use Cro::HTTP::Router;
use Cro::Transform;
use Cro::TCP;
use Cro::WebSocket::FrameParser;
use Cro::WebSocket::Handler;
use Cro::WebSocket::FrameSerializer;
use Cro::WebSocket::MessageParser;
use Cro::WebSocket::MessageSerializer;

sub web-socket(&handler) is export {
    my $magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

    my $request = request;
    my $response = response;

    unless $request.header('sec-websocket-version') eq '13' {
        $response.status = 426;
        $response.append-header('Sec-WebSocket-Version', '13');
    };

    # Bad request checking
    if !($request.method eq 'GET')
    || !($request.http-version eq '1.1')
    || !$request.has-header('host')
    || !(($request.header('Connection') // '').lc eq 'Upgrade')
    || decode-base64($request.header('sec-websocket-key') // '', :bin).elems != 16 {
        bad-request;
    };

    my $key = $request.header('sec-websocket-key');

    $response.status = 101;
    $response.append-header('Upgrade', 'websocket');
    $response.append-header('Connection', 'Upgrade');
    $response.append-header('Sec-WebSocket-Accept', encode-base64(sha1($key ~ $magic), :str));

    my Cro::Transform $pipeline;
    $pipeline = Cro.compose(Cro::WebSocket::FrameParser.new(mask-required => True),
                            Cro::WebSocket::MessageParser.new,
                            Cro::WebSocket::Handler.new(&handler),
                            Cro::WebSocket::MessageSerializer.new,
                            Cro::WebSocket::FrameSerializer.new(mask => False));
    $response.set-body-byte-stream:
        $pipeline.transformer(
            $request.body-byte-stream.map(-> $data { Cro::TCP::Message.new(:$data) })
        ).map({ note $_.data; $_.data}); # XXX Remove debug note
}
