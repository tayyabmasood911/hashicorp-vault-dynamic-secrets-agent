pid_file = "/home/vault/pid"

vault {
  address = "https://vault.internal:8200"
  retry {
    num_retries = 5
  }
}

auto_auth {
  method "kubernetes" {
    mount_path = "auth/kubernetes"
    config = {
      role = "app-role"
    }
  }

  sink "file" {
    config = {
      path = "/home/vault/.vault-token"
      mode = 0640
    }
  }
}

cache {
  use_auto_auth_token = true
}

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = true
}

template {
  source      = "/etc/vault/template-database.ctmpl"
  destination = "/vault/secrets/database.env"
  perms       = "0600"
  command     = "kill -HUP 1 || true"
}
