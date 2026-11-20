import Foundation

/// tterm 제어 소켓 클라이언트.
///
/// tterm은 `$TMPDIR/tterm/control.sock` 에 유닉스 도메인 소켓을 연다 (tterm `src/core/control_socket.rs`).
/// 한 줄에 JSON 하나를 보내고 한 줄로 응답을 받는다. 터미널은 tty 경로(`/dev/ttys012`)로 가리킨다.
enum TtermControl {
    struct ControlError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static var socketPath: String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("tterm/control.sock")
    }

    /// tty의 터미널에 `text` 를 붙여넣고, `submit` 이면 Enter까지 보낸다.
    static func sendInput(tty: String, text: String, submit: Bool) async throws {
        _ = try await request(["cmd": "input", "tty": tty, "text": text, "submit": submit])
    }

    /// 요청 하나를 보내고 응답을 받는다. 응답의 `ok` 가 거짓이면 그 `error` 로 실패한다.
    static func request(_ body: [String: Any]) async throws -> [String: Any] {
        try await Task.detached(priority: .userInitiated) {
            let data = try JSONSerialization.data(withJSONObject: body) + Data([0x0A])
            let reply = try roundTrip(data)
            guard let obj = try? JSONSerialization.jsonObject(with: reply) as? [String: Any] else {
                throw ControlError(message: "tterm의 응답을 읽지 못했습니다.")
            }
            guard obj["ok"] as? Bool == true else {
                throw ControlError(message: "tterm이 요청을 처리하지 못했습니다: \(obj["error"] as? String ?? "알 수 없는 오류")")
            }
            return obj
        }.value
    }

    /// 연결 → 한 줄 쓰기 → 한 줄 읽기 (블로킹, 5초 제한)
    private static func roundTrip(_ line: Data) throws -> Data {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlError(message: "소켓을 만들지 못했습니다.") }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count < capacity else { throw ControlError(message: "tterm 소켓 경로가 너무 깁니다.") }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            buf.copyBytes(from: pathBytes)
            buf[pathBytes.count] = 0
        }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            throw ControlError(message: "tterm에 연결하지 못했습니다. 제어 소켓을 지원하는 tterm이 실행 중인지 확인하세요.")
        }

        try line.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n <= 0 { throw ControlError(message: "tterm에 요청을 보내지 못했습니다.") }
                offset += n
            }
        }

        var reply = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while !reply.contains(0x0A) {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { throw ControlError(message: "tterm의 응답이 없습니다.") }
            reply.append(buf, count: n)
        }
        return reply.prefix(while: { $0 != 0x0A })
    }
}
