FROM python:3.11-slim

WORKDIR /app

# Simple HTTP server for IAM testing
RUN echo 'from http.server import HTTPServer, BaseHTTPRequestHandler\n\
class Handler(BaseHTTPRequestHandler):\n\
    def do_GET(self):\n\
        self.send_response(200)\n\
        self.send_header("Content-type", "text/plain")\n\
        self.end_headers()\n\
        self.wfile.write(b"OK")\n\
if __name__ == "__main__":\n\
    server = HTTPServer(("0.0.0.0", 8080), Handler)\n\
    server.serve_forever()' > server.py

EXPOSE 8080

CMD ["python", "server.py"]

