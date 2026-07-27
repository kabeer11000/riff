rom fastembed import TextEmbedding

# Load the model ONCE globally when your Render server starts.
# We use the v2 quantized version for absolute minimum RAM usage.
model = TextEmbedding(model_name="sentence-transformers/all-MiniLM-L6-v2") 

def generate_item_embedding(title: str, tags: list, description: str, platform: str):
    # 1. TRUNCATE THE DESCRIPTION (Crucial for CPU limits)
    # Never embed a full YouTube description. They are filled with sponsor links 
    # and will burn your CPU compute time for no reason. 
    safe_description = description[:200] if description else ""
    
    # 2. Join tags safely
    joined_tags = " ".join(tags) if tags else ""
    
    # 3. Create the final unified string
    if platform == "youtube":
        metadata_string = f"{title} {joined_tags} {safe_description}"
    elif platform == "spotify":
        metadata_string = f"{title} {joined_tags}" 
        
    # 4. Generate the embedding (FastEmbed returns a generator, so we cast to list)
    # This will execute in milliseconds on your 2-vCPU instance.
    embeddings_generator = model.embed([metadata_string])
    vector_array = list(embeddings_generator)[0].tolist()
    
    return vector_array

# Example usage:
vector = generate_item_embedding(
    title="Mechanical Keyboard ASMR Typing",
    tags=["keyboard", "asmr", "typing", "switches"],
    description="Typing test of my custom mechanical keyboard built with lubed linear switches. Links to buy parts below! Patreon...",
    platform="youtube"
)

print(f"Generated {len(vector)} dimensions successfully.")
