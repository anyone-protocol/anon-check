job "anon-check-dev" {
  datacenters = ["ator-fin"]
  type        = "service"
  namespace   = "ator-network"

  group "anon-check-dev-group" {
    count = 1

    volume "anon-check-data" {
      type      = "host"
      read_only = false
      source    = "anon-check-dev"
    }

    network {
      mode = "bridge"
      port "http-port" {
        static       = 9088
        to           = 8000
        host_network = "wireguard"
      }
      port "orport" {
        static = 9091
      }
    }

    ephemeral_disk {
      migrate = true
      sticky  = true
    }

    task "anon-check-service-dev-task" {
      driver = "docker"

      template {
        data        = <<EOH
	{{- range nomadService "collector-dev" }}
  	    COLLECTOR_HOST="http://{{ .Address }}:{{ .Port }}"
	{{ end -}}
            INTERVAL_MINUTES="5"
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
        ports      = ["http-port"]
        volumes    = [
          "local/logs/:/opt/check/data/logs"
        ]
      }

      vault {
        policies = ["ator-network-read"]
      }

      resources {
        cpu    = 256
        memory = 256
      }

      service {
        name = "anon-check-dev"
        port = "http-port"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.check-dev.rule=Host(`check-dev.dmz.ator.dev`)",
          "traefik.http.routers.check-dev.entrypoints=https",
          "traefik.http.routers.check-dev.tls=true",
          "traefik.http.routers.check-dev.tls.certresolver=atorresolver",

          "traefik.http.routers.any1-check-dev.rule=Host(`check-dev.en.anyone.tech`)",
          "traefik.http.routers.any1-check-dev.entrypoints=https",
          "traefik.http.routers.any1-check-dev.tls=true",
          "traefik.http.routers.any1-check-dev.tls.certresolver=anyoneresolver",
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

    task "anon-check-relay-dev-task" {
      driver = "docker"

      volume_mount {
        volume      = "anon-check-data"
        destination = "/var/lib/anon"
        read_only   = false
      }

      config {
        # todo - use latest commit tag - https://github.com/anyone-protocol/jira-confluence/issues/224
        image      = "ghcr.io/anyone-protocol/ator-protocol-dev:a72d294467112abb78ad6982259067af4574e88d"
        volumes    = [
          "local/anonrc:/etc/anon/anonrc"
        ]
      }

      vault {
        policies = ["ator-network-read"]
      }

      resources {
        cpu    = 256
        memory = 256
      }

      service {
        name = "anon-check-relay-dev"
        tags = [ "logging" ]
      }

      template {
        change_mode = "noop"
        data        = <<EOH
DataDirectory /var/lib/anon/anon-data

User anond

AgreeToTerms 1

Nickname AnonCheckRelayDev

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
