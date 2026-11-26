variable "anon_check_tag" {
  type        = string
  description = "The anon-check container image tag to deploy for the anon-check-service-live-task"
  // Deploys are manual, so this pin is what ships. Bump it to the commit the
  // image was built from, or override with -var=anon_check_tag=<sha>.
  default     = "61fad827db196f23b621411d809f56ec19ef790a"
}
variable "anyone_client_tag" {
  type        = string
  description = "The anyone client container image tag to deploy for the anon-check-relay-live-task"
  default     = "631f3c9805513000a13113e8b48b6b4ce262689b" // v0.4.11.0-beta
}

job "anon-check-live" {
  datacenters = ["ator-fin"]
  type        = "service"
  namespace   = "live-network"

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

      consul {}

      template {
        data        = <<-EOH
	      {{- range service "collector-live" }}
  	    COLLECTOR_HOST="http://{{ .Address }}:{{ .Port }}"
	      {{- end }}
        INTERVAL_MINUTES="60"
        EOH
        destination = "local/config.env"
        env         = true
      }

      volume_mount {
        volume      = "anon-check-data"
        destination = "/opt/check/data"
        read_only   = false
      }

      config {
        image      = "ghcr.io/anyone-protocol/anon-check:${var.anon_check_tag}"
        image_pull_timeout = "15m"
        ports      = ["http-port"]
        volumes    = [
          "local/logs/:/opt/check/data/logs",
        ]
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
            grace = "15m"
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
        image      = "ghcr.io/anyone-protocol/ator-protocol-dev-amd64:${var.anyone_client_tag}"
        image_pull_timeout = "15m"
        volumes    = [
          "local/anonrc:/etc/anon/anonrc"
        ]
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
        data        = <<-EOH
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
