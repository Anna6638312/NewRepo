terraform {
  required_providers {
    azurecaf = {
      source  = "aztfmod/azurecaf"
      version = ">=1.2.22"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.34.0"
    }
  }
}

resource "azurecaf_name" "frontdoor" {
  name          = var.application_name
  resource_type = "azurerm_cdn_frontdoor_profile"
  suffixes      = [var.environment]
}

resource "azurerm_cdn_frontdoor_profile" "frontdoor" {
  name                = azurecaf_name.frontdoor.result
  resource_group_name = var.resource_group
  sku_name            = var.azure_frontdoor_sku
}

locals {
  endpoint_uris = {
    for endpoint in module.endpoint :
    endpoint.cdn_frontdoor_endpoint_uri => endpoint.cdn_frontdoor_endpoint_uri
  }
}

module "endpoint" {
  count = length(var.endpoint_settings)

  source = "./endpoint"

  frontdoor_profile_id = azurerm_cdn_frontdoor_profile.frontdoor.id
  location             = var.location

  endpoint_name            = var.endpoint_settings[count.index].endpoint_name
  web_app_hostname         = var.endpoint_settings[count.index].web_app_hostname
  web_app_id               = var.endpoint_settings[count.index].web_app_id
  private_link_target_type = var.endpoint_settings[count.index].private_link_target_type
}

resource "azurerm_cdn_frontdoor_firewall_policy" "waf" {
  count = var.enable_waf ? 1 : 0

  name                = "wafpolicymicrosoftdefaultruleset21"
  resource_group_name = var.resource_group
  sku_name            = azurerm_cdn_frontdoor_profile.frontdoor.sku_name
  mode                = "Prevention"
  enabled             = true

  managed_rule {
    type    = "Microsoft_DefaultRuleSet"
    version = "2.1"
    action  = "Block"
  }
}

resource "azurerm_cdn_frontdoor_security_policy" "web_app_waf" {
  count = var.enable_waf ? 1 : 0

  name                     = "WAF-Security-Policy"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.frontdoor.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.waf[0].id

      association {
        patterns_to_match = ["/*"]

        # domain {
        #   cdn_frontdoor_domain_id = module.endpoint.cdn_frontdoor_endpoint_id
        # }

        dynamic "domain" {
          for_each = module.endpoint

          content {
            cdn_frontdoor_domain_id = module.endpoint[domain.key].cdn_frontdoor_endpoint_id
          }
        }
      }
    }
  }
}
