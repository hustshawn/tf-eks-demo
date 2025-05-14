export CONCURRENCY=20
export NUM_PROMPTS=100
export MODEL=deepseek-ai/DeepSeek-R1-Distill-Qwen-32B
export TOKENIZER=Qwen/Qwen2.5-32B-Instruct
genai-perf profile --url sglang-leader:40000 \
  -m $MODEL \
  --service-kind openai \
  --endpoint-type completions \
  --num-prompts $NUM_PROMPTS \
  --synthetic-input-tokens-mean 200 \
  --synthetic-input-tokens-stddev 50 \
  --output-tokens-mean 300 \
  --output-tokens-stddev 100 \
  --concurrency $CONCURRENCY \
  --streaming \
  --tokenizer $TOKENIZER \
  --warmup-request-count $CONCURRENCY