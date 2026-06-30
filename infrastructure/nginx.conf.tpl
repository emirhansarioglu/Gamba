upstream gamba_backend {
%{ for ip in backend_ips ~}
    server ${ip}:8000;
%{ endfor ~}
}

server {
    listen 80;

    location /api/ {
        proxy_pass         http://gamba_backend;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /health {
        proxy_pass         http://gamba_backend;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
    }

    location /metrics {
        proxy_pass         http://gamba_backend;
        proxy_set_header   Host $host;
    }

    location / {
        root       /var/www/gamba;
        index      index.html;
        try_files  $uri $uri/ /index.html;
    }
}
