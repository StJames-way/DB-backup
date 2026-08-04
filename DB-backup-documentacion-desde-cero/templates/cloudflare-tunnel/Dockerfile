FROM cloudflare/cloudflared:2026.7.2

# TUNNEL_TOKEN is supplied as a Fly secret and consumed automatically.
ENTRYPOINT ["cloudflared", "tunnel", "--no-autoupdate", "--protocol", "quic", "--loglevel", "info", "run"]
