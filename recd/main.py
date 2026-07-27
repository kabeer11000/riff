import json
import redis
from fastembed import TextEmbedding
import os
import libsql

# Connect to Upstash Redis
#
r = redis.Redis.from_url("rediss://default:gQAAAAAAAsPZAAIgcDEwMTQ2MWNiYzUwOGI0YTI0OGZhOWNhM2MyZmE5NTJiMA@cunning-toucan-181209.upstash.io:6379", decode_responses=True)
db = libsql.connect(
    database=  os.environ["TURSO_DATABASE_URL"],
    auth_token=os.environ["TURSO_AUTH_TOKEN"],
)
# Load model once
model = TextEmbedding(model_name="sentence-transformers/all-MiniLM-L6-v2", threads=1)

print("Worker started. Listening for embedding jobs...")

while True:
    # BRPOP blocks until a message arrives in 'embedding_queue'. No CPU wasted while waiting.
    queue_name, message_json = r.brpop('embedding_queue')

    job = json.loads(message_json)
    print(f"Processing item {job['item_id']}...")

    # 1. Generate Embedding
    vector = list(model.embed([job['text']]))[0].tolist()

    # 2. Save to Turso (pseudo-code)
    # turso_client.execute("UPDATE items SET vector = ? WHERE id = ?", [vector, job['item_id']])

    print(f"Item {job['item_id']} completed.")
