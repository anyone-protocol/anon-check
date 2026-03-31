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
        image      = "ghcr.io/anyone-protocol/anon-check:DEPLOY_TAG"
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
            grace = "5m"
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
        image      = "ghcr.io/anyone-protocol/ator-protocol:b0745662741bb2ab7cd6cbbcae6382e2fabf9e7b" // v0.4.9.13
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
