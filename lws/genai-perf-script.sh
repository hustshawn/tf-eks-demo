export CONCURRENCY=20
export NUM_PROMPTS=100
export MODEL=deepseek-ai/DeepSeek-R1
export TOKENIZER=deepseek-ai/DeepSeek-R1
genai-perf profile --url deepseek-r1-leader \
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