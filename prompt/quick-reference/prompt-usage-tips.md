# Prompt Usage Tips

```markdown
## Getting Best Results

1. Always include the constraint block - paste the KodeKloud limits at the end
   of any prompt to prevent the AI from suggesting incompatible resources.

2. Run prompts in order - each phase builds on the previous.
   Phase 4 (ArgoCD) references folder structure from Phase 1 (Terraform).

3. One prompt per session - each prompt is designed to fit in a single AI session.

4. Regenerate with context - if continuing a prompt, paste the previous output
   as context: "Here is what was generated previously: [paste]. Now continue with..."

5. Local LLM fallback - for AI prompts (Phase 8, 9), if API costs are a concern:
   - Install Ollama: curl -fsSL https://ollama.com/install.sh | sh
   - Pull model: ollama pull llama3.2 (for generation)
   - Pull model: ollama pull nomic-embed-text (for embeddings)
   - Change LLM_PROVIDER=ollama in all configs

6. Cost-first mindset - always prefix prompts with:
   "This is for KodeKloud playground with tight resource limits.
   Prioritise lowest possible SKU and resource usage."
```
