package gcp

import future.keywords.if

test_deny_gke_too_many_nodes if {
  count(deny) > 0 with input as {
    "resource_changes": [{
      "address": "google_container_node_pool.main",
      "type": "google_container_node_pool",
      "change": {
        "actions": ["create"],
        "after": {
          "node_count": 5,
          "location": "us-central1",
          "node_config": [{"machine_type": "e2-standard-2"}]
        }
      }
    }]
  }
}

test_allow_gke_three_nodes if {
  count(deny) == 0 with input as {
    "resource_changes": [{
      "address": "google_container_node_pool.main",
      "type": "google_container_node_pool",
      "change": {
        "actions": ["create"],
        "after": {
          "node_count": 3,
          "location": "us-central1",
          "node_config": [{"machine_type": "e2-standard-2"}]
        }
      }
    }]
  }
}

test_deny_gke_autopilot if {
  count(deny) > 0 with input as {
    "resource_changes": [{
      "address": "google_container_cluster.main",
      "type": "google_container_cluster",
      "change": {
        "actions": ["create"],
        "after": {
          "enable_autopilot": true,
          "initial_node_count": 1,
          "location": "us-central1"
        }
      }
    }]
  }
}

test_deny_primitive_iam_role if {
  count(deny) > 0 with input as {
    "resource_changes": [{
      "address": "google_project_iam_binding.owner",
      "type": "google_project_iam_binding",
      "change": {
        "actions": ["create"],
        "after": {
          "role": "roles/owner",
          "location": "us-central1"
        }
      }
    }]
  }
}

test_deny_non_us_region if {
  count(deny) > 0 with input as {
    "resource_changes": [{
      "address": "google_storage_bucket.eu",
      "type": "google_storage_bucket",
      "change": {
        "actions": ["create"],
        "after": {
          "location": "europe-west1",
          "versioning": [{"enabled": true}]
        }
      }
    }]
  }
}
