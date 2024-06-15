import os
import logging
from fastapi import FastAPI
from dotenv import load_dotenv


load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()

from chat_endpoint import chat
from file_analysis_endpoint import file_analysis, reset_session

app.include_router(chat.router, prefix="/chat")
app.include_router(file_analysis.router, prefix="/file-analysis")
app.include_router(reset_session.router, prefix="/reset-session")

@app.get("/")
def read_root():
    return {"Hello": "World"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
