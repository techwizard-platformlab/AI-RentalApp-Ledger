# k8s-assistant — AI-Powered Kubernetes Pod Analyser

Diagnoses failing pods using LLM analysis and optionally remediates them.

## Quick Start

```bash
cd ai-tools/k8s-assistant
pip install -r requirements.txt

# Option 1: Ollama (free, local)
ollama pull llama3.2
python k8s-assistant.py --namespace rental-dev --watch --llm ollama

# Option 2: Groq (free tier, fast)
export GROQ_API_KEY=<your-key>
python k8s-assistant.py --namespace rental-dev --watch --llm groq

# Option 3: Claude Haiku (cheapest Anthropic)
export ANTHROPIC_API_KEY=<your-key>
python k8s-assistant.py --namespace rental-dev --watch --llm claude
```

## Usage

```bash
# Watch namespace for failing pods (poll every 30s)
python k8s-assistant.py --namespace rental-dev --watch

# Analyse a specific pod
python k8s-assistant.py --pod api-gateway-abc123 --namespace rental-dev --analyse

# Offer remediation (dry-run first)
python k8s-assistant.py --namespace rental-dev --auto-fix --dry-run

# Actually remediate
python k8s-assistant.py --pod api-gateway-abc123 --namespace rental-dev --analyse --auto-fix
```

## RBAC Setup

```bash
# Read-only (default)
kubectl apply -f rbac.yaml

# Also grant auto-fix permissions
kubectl apply -f rbac.yaml --selector=role=auto-fix
```

## Discord Notifications

```bash
export DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
```

Critical findings automatically post to Discord.

## Running in-cluster (CronJob)

See the anomaly_detector for an example CronJob that calls k8s-assistant
on detected anomalies.
