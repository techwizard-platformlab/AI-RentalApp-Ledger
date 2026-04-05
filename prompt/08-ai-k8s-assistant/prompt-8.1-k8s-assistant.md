# Prompt 8.1 - AI Kubernetes Assistant: Pod Log Analyser

```
Act as a Python AI engineer and Kubernetes expert.

CONTEXT:
- Cluster: AKS / GKE
- Stack: Python, Kubernetes Python client, LLM API
- LLM: Use free/cheapest option - in order of preference:
  1. Ollama (local, free - llama3.2 or mistral)
  2. Groq API (free tier, fast - llama3-8b)
  3. Claude claude-haiku (cheapest Anthropic model)
- Goal: Diagnose pod issues automatically, suggest fixes

TASK:
Build a Python CLI tool: k8s-assistant.py

### Features:

#### 1. Pod Log Fetcher
```python
# Functions to implement:
def get_failing_pods(namespace: str) -> list[dict]
def get_pod_logs(pod_name: str, namespace: str, lines: int = 100) -> str
def get_pod_events(pod_name: str, namespace: str) -> list[dict]
def get_pod_status(pod_name: str, namespace: str) -> dict
```

#### 2. LLM Error Summariser
```python
def analyse_logs_with_llm(
    pod_name: str,
    logs: str,
    events: list,
    status: dict,
    llm_provider: str = "ollama"
) -> dict:
    """
    Returns:
    {
      "error_type": "OOMKilled | CrashLoopBackOff | ImagePullError | ...",
      "root_cause": "plain English explanation",
      "severity": "critical | warning | info",
      "suggested_fixes": ["fix 1", "fix 2", "fix 3"],
      "kubectl_commands": ["kubectl describe ...", "kubectl logs ..."],
      "documentation_links": ["https://..."]
    }
    """
```

#### 3. Auto-Remediation Actions (with confirmation prompt)
- Restart pod: kubectl rollout restart deployment/{name}
- Rollback deployment: kubectl rollout undo deployment/{name}
- Scale down/up: kubectl scale deployment/{name} --replicas=N
- Each action requires user confirmation: "Execute fix? [y/N]"
- RBAC: default read-only; optional elevated role when --auto-fix is used

#### 4. CLI Interface
```bash
# Usage examples:
python k8s-assistant.py --namespace rental-dev --watch
python k8s-assistant.py --pod api-gateway-xxx --analyse
python k8s-assistant.py --namespace rental-dev --auto-fix --dry-run
```

#### 5. Notification Integration
- On Critical finding: send Discord notification with summary
- Include: pod name, error type, suggested fix, kubectl command

INCLUDE:
- requirements.txt (kubernetes, openai/groq/ollama client, rich for CLI output)
- LLM prompt template (system prompt for K8s expert context)
- How to run with Ollama locally (ollama pull llama3.2)
- Kubernetes RBAC: ServiceAccount with read-only pod/log access
- Optional Role/RoleBinding for auto-fix when explicitly enabled

OUTPUT: Complete k8s-assistant.py + requirements.txt + rbac.yaml + README
```
