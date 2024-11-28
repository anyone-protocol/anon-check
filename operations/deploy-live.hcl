job "anon-check-live" {
  datacenters = ["ator-fin"]
  type        = "service"
  namespace   = "ator-network"

  update {
    max_parallel      = 1
    healthy_deadline  = "15m"
    progress_deadline = "20m"
  }

  group "anon-check-live-group" {
    count = 1

    volume "anon-check-data" {
      type      = "host"
      read_only = false
      source    = "anon-check-live"
    }

    network {
      mode = "bridge"
      port "http-port" {
        static       = 9288
        to           = 8000
        host_network = "wireguard"
      }
      port "orport" {
        static = 9291
      }
    }

    ephemeral_disk {
      migrate = true
      sticky  = true
    }

    task "anon-check-service-live-task" {
      driver = "docker"

      template {
        data        = <<EOH
	{{- range nomadService "collector-live" }}
  	    COLLECTOR_HOST="http://{{ .Address }}:{{ .Port }}"
	{{ end -}}
            INTERVAL_MINUTES="60"
            EOH
        destination = "secrets/file.env"
        env         = true
      }

      volume_mount {
        volume      = "anon-check-data"
        destination = "/opt/check/data"
        read_only   = false
      }

      config {
        image      = "ghcr.io/anyone-protocol/anon-check:DEPLOY_TAG"
        image_pull_timeout = "15m"
        ports      = ["http-port"]
        volumes    = [
          "local/logs/:/opt/check/data/logs",
        ]
      }

      vault {
        policies = ["ator-network-read"]
      }

      resources {
        cpu    = 256
        memory = 512
      }

      service {
        name = "anon-check-live"
        port = "http-port"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.check-live.rule=Host(`check-live.dmz.ator.dev`)",
          "traefik.http.routers.check-live.entrypoints=https",
          "traefik.http.routers.check-live.tls=true",
          "traefik.http.routers.check-live.tls.certresolver=atorresolver",

          "traefik.http.routers.any1-check-live.rule=Host(`check.en.anyone.tech`)",
          "traefik.http.routers.any1-check-live.entrypoints=https",
          "traefik.http.routers.any1-check-live.tls=true",
          "traefik.http.routers.any1-check-live.tls.certresolver=anyoneresolver",
          "logging"
        ]
        check {
          name     = "Anon check web server check"
          type     = "http"
          port     = "http-port"
          path     = "/"
          interval = "10s"
          timeout  = "10s"
          check_restart {
            limit = 10
            grace = "30s"
          }
        }
      }
    }

    task "anon-check-relay-live-task" {
      driver = "docker"

      volume_mount {
        volume      = "anon-check-data"
        destination = "/var/lib/anon"
        read_only   = false
      }

      config {
        image      = "ghcr.io/anyone-protocol/ator-protocol:5ef03ae3ddb9efe2ece3b1ec378292a8ea1bc7a3" // v0.4.9.8
        image_pull_timeout = "15m"
        volumes    = [
          "local/anonrc:/etc/anon/anonrc"
        ]
      }

      vault {
        policies = ["ator-network-read"]
      }

      resources {
        cpu    = 256
        memory = 1024
      }

      service {
        name = "anon-check-relay-live"
        tags = [ "logging" ]
      }

      template {
        change_mode = "noop"
        data        = <<EOH
DataDirectory /var/lib/anon/anon-data

User anond

AgreeToTerms 1

Nickname AnonCheckRelayLive

FetchDirInfoEarly 1
FetchDirInfoExtraEarly 1
FetchUselessDescriptors 1
UseMicrodescriptors 0
DownloadExtraInfo 1

ORPort {{ env `NOMAD_PORT_orport` }}
        EOH
        destination = "local/anonrc"
      }
    }
  }
}
