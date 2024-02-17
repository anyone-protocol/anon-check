job "anon-check-dev" {
  datacenters = ["ator-fin"]
  type        = "service"
  namespace   = "ator-network"

  group "anon-check-dev-group" {
    count = 1

#    volume "anon-check-data" {
#      type      = "host"
#      read_only = false
#      source    = "anon-check-dev"
#    }

    network {
#      mode = "bridge"
      port "http-port" {
        static = 9088
        to     = 8000
#        host_network = "wireguard"
      }
    }

    ephemeral_disk {
      migrate = true
      sticky  = true
    }

    task "anon-check-service-dev-task" {
      driver = "docker"

      template {
        data = <<EOH
	{{- range nomadService "collector-dev" }}
  	    COLLECTOR_HOST="http://{{ .Address }}:{{ .Port }}"
	{{ end -}}
            INTERVAL_MINUTES="1"
            EOH
        destination = "secrets/file.env"
        env         = true
      }

#      volume_mount {
#        volume      = "anon-check-data"
#        destination = "/opt/check/data"
#        read_only   = false
#      }

      config {
        image   = "svforte/anon-check:latest-dev"
        force_pull = true
        ports   = ["http-port"]
        volumes = [
#          "local/logs/:/opt/check/data/logs",
          "local/data/:/opt/check/data/"
        ]
      }

#      vault {
#      	policies = ["ator-network-read"]
#      }

      resources {
        cpu    = 256
        memory = 256
      }

      service {
        name = "anon-check-dev"
        port = "http-port"
        #        tags = [
        #          "traefik.enable=true",
        #          "traefik.http.routers.deb-repo.entrypoints=https",
        #          "traefik.http.routers.deb-repo.rule=Host(`dev.anon-check.dmz.ator.dev`)",
        #          "traefik.http.routers.deb-repo.tls=true",
        #          "traefik.http.routers.deb-repo.tls.certresolver=atorresolver",
        #        ]
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

#      volume_mount {
#        volume      = "anon-check-data"
#        destination = "/var/lib/anon"
#        read_only   = true
#      }

      config {
        image   = "svforte/anon-dev"
        force_pull = true
        volumes = [
          "local/anonrc:/etc/anon/anonrc",
          "local/data:/var/lib/anon"
        ]
      }

#      vault {
#      	policies = ["ator-network-read"]
#      }

      resources {
        cpu    = 256
        memory = 256
      }

      template {
        change_mode = "noop"
        data        = <<EOH
DataDirectory /var/lib/anon/anon-data

Nickname ForteAnonCheckRelay

FetchDirInfoEarly 1
FetchDirInfoExtraEarly 1
FetchUselessDescriptors 1
UseMicrodescriptors 0
DownloadExtraInfo 1
        EOH
        destination = "local/anonrc"
      }
    }
  }
}
