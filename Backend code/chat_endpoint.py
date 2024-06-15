import os
import aiofiles
import asyncio
import logging
import uuid
import numpy as np
import pandas as pd
from fastapi import APIRouter, UploadFile, File, Form, HTTPException
from pydantic import BaseModel
from docx import Document as DocxDocument
from PyPDF2 import PdfReader
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_openai import OpenAIEmbeddings
from langchain.vectorstores import FAISS
from openai import OpenAI
from langchain_huggingface import HuggingFaceEndpoint, ChatHuggingFace
from langchain_core.messages import HumanMessage, SystemMessage
from dotenv import load_dotenv

load_dotenv()

HUGGINGFACE_API_KEY = os.getenv("HUGGINGFACEHUB_API_TOKEN")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")


router = APIRouter()

phi_3_llm = HuggingFaceEndpoint(
    repo_id="microsoft/Phi-3-mini-4k-instruct",
    task="text-generation",
    max_new_tokens=512,
    do_sample=False,
    repetition_penalty=1.03,
    headers={"Authorization": f"Bearer {HUGGINGFACE_API_KEY}"}
)

meta_llama_3_llm = HuggingFaceEndpoint(
    repo_id="meta-llama/Meta-Llama-3-8B-Instruct",
    task="text-generation",
    max_new_tokens=512,
    do_sample=False,
    repetition_penalty=1.03,
    headers={"Authorization": f"Bearer {HUGGINGFACE_API_KEY}"}
)

TEMP_STORAGE = {}

class FileResponse(BaseModel):
    response: str
    session_id: str

@router.post("/", response_model=FileResponse)
async def file_analysis(model: str = Form(...), prompt: str = Form(...), file: UploadFile = File(None), session_id: str = Form(None)):
    start_time = datetime.now()
    logger.info(f"Received file analysis request at {start_time}, model: {model}, prompt: {prompt}, file: {file.filename if file else 'None'}, session_id: {session_id}")

    new_session_id = None
    vectorstore = None
    try:
        if not file and not session_id:
            logger.error("No file uploaded and no session ID provided.")
            raise HTTPException(status_code=400, detail="No file uploaded and no session ID provided. Please upload a file.")

        if file:
            logger.info("Processing file upload.")
            file_ext = os.path.splitext(file.filename)[1].lower()
            if file_ext not in [".pdf", ".csv", ".docx", ".txt"]:
                logger.error(f"Unsupported file format: {file_ext}")
                raise HTTPException(status_code=400, detail="Unsupported file format")

            async with aiofiles.tempfile.NamedTemporaryFile(delete=False, suffix=file_ext) as temp_file:
                await temp_file.write(await file.read())
                temp_file_path = temp_file.name

            logger.info(f"Temporary file created at {temp_file_path} with extension {file_ext}")

            async def load_documents(file_path: str) -> str:
                ext = os.path.splitext(file_path)[1].lower()
                logger.info(f"File extension determined: {ext}")
                if ext == ".pdf":
                    return await asyncio.to_thread(get_pdf_text, file_path)
                elif ext == ".csv":
                    return await asyncio.to_thread(get_csv_text, file_path)
                elif ext == ".docx":
                    return await asyncio.to_thread(get_docx_text, file_path)
                elif ext == ".txt":
                    return await asyncio.to_thread(get_txt_text, file_path)
                else:
                    logger.error(f"Unsupported file format: {ext}")
                    raise HTTPException(status_code=400, detail="Unsupported file format")

            document_text = await load_documents(temp_file_path)

            text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
            text_chunks = await asyncio.to_thread(text_splitter.split_text, document_text)

            vectorstore = await asyncio.to_thread(get_vectorstore, text_chunks)

            # Generate a session ID for this file upload
            new_session_id = str(uuid.uuid4())
            TEMP_STORAGE[new_session_id] = {
                "vectorstore": vectorstore
            }
            logger.info(f"Current TEMP_STORAGE contents: {TEMP_STORAGE}")

            logger.info(f"New session ID generated: {new_session_id}")

        if session_id and not vectorstore:
            logger.info(f"Session ID provided: {session_id}")
            if session_id not in TEMP_STORAGE:
                logger.error(f"Session ID {session_id} not found in TEMP_STORAGE")
                raise HTTPException(status_code=400, detail="Session ID not found. Please upload the file again.")
            else:
                vectorstore = TEMP_STORAGE[session_id]["vectorstore"]

        # Continue with the analysis logic regardless of whether file or session ID is provided
        embedding_model = OpenAIEmbeddings(openai_api_key=OPENAI_API_KEY)
        prompt_embedding = await asyncio.to_thread(embedding_model.embed_documents, [prompt])
        normalized_prompt_embedding = normalize_l2(np.array(prompt_embedding[0])).tolist()

        similar_texts = await asyncio.to_thread(vectorstore.similarity_search_by_vector, normalized_prompt_embedding)

        similar_text_content = " ".join([text.page_content for text in similar_texts])
        complete_prompt = f"text:{similar_text_content}\n\nUser prompt: {prompt}"

        logger.info(f"Complete prompt prepared for model: {complete_prompt}")

        if model == "Phi-3":
            chat_model = ChatHuggingFace(llm=phi_3_llm)
            messages = [
                SystemMessage(content="Answer the questions based on the text given. Use the information directly from the text when available. If the answer is not explicitly stated, use logical inference based on the context of the text. If the text provides enough context to make a reasonable inference, do so. Only respond with 'could not find the answer' if there is no way to reasonably infer the answer from the given information."),
                HumanMessage(content=complete_prompt),
            ]
            response = await asyncio.to_thread(chat_model.invoke, messages)
            result = response.content
        elif model == "Mistral-7B":
            repo_id = "mistralai/Mistral-7B-Instruct-v0.2"
            headers = {"Authorization": f"Bearer {HUGGINGFACE_API_KEY}"}
            formatted_prompt = f"[INST] Below is a context followed by a user query.\n\nContext:\n{similar_text_content}\n\nUser query: {prompt}\n\n[/INST]"
            payload = {"inputs": formatted_prompt}
            response = await query_llm(api_url, headers, payload)
            result = clean_response(response, prompt)
        elif model == "Meta-Llama-3":
            chat_model = ChatHuggingFace(llm=meta_llama_3_llm)
            messages = [
                SystemMessage(content="Answer the questions based on the text given"),
                HumanMessage(content=complete_prompt),
            ]
            response = await asyncio.to_thread(chat_model.invoke, messages)
            result = response.content
        elif model == "GPT-3.5":
            client = OpenAI(api_key=OPENAI_API_KEY)
            completion = await asyncio.to_thread(client.chat.completions.create,
                model="gpt-3.5-turbo",
                messages=[
                    {"role": "system", "content": "Answer the questions based on the text given"},
                    {"role": "user", "content": complete_prompt}
                ]
            )
            result = completion.choices[0].message.content
        else:
            raise ValueError("Invalid model specified")
    except Exception as e:
        logger.error(f"Error processing file analysis request: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if file:
            logger.info(f"Deleting temporary file at {temp_file_path}")
            os.remove(temp_file_path)

    end_time = datetime.now()
    logger.info(f"Completed file analysis request at {end_time}, duration: {end_time - start_time}")
    return {"response": result, "session_id": new_session_id if new_session_id else session_id}

@router.post("/reset-session")
async def reset_session(session_id: str = Form(...)):
    if session_id in TEMP_STORAGE:
        del TEMP_STORAGE[session_id]
        logger.info(f"Current TEMP_STORAGE contents: {TEMP_STORAGE}")

        return {"status": "success", "message": "Session reset successfully."}
    else:
        raise HTTPException(status_code=400, detail="Session ID not found.")

async def query_llm(api_url: str, headers: dict, payload: dict) -> str:
    async with aiohttp.ClientSession() as session:
        async with session.post(api_url, headers=headers, json=payload) as response:
            response_json = await response.json()
            if isinstance(response_json, list):
                return response_json[0]['generated_text']
            return response_json

def clean_response(response: str, prompt: str) -> str:
    response = response.replace("[INST]", "").replace("[/INST]", "").strip()
    parts = response.split(prompt)
    if len(parts) > 1:
        return parts[1].strip()
    return response

def get_pdf_text(pdf_path: str) -> str:
    text = ""
    pdf_reader = PdfReader(pdf_path)
    for page in pdf_reader.pages:
        text += page.extract_text()
    return text

def get_csv_text(file_path: str) -> str:
    df = pd.read_csv(file_path)
    return df.to_string()

def get_docx_text(file_path: str) -> str:
    doc = DocxDocument(file_path)
    return "\n".join([para.text for para in doc.paragraphs])

def get_txt_text(file_path: str) -> str:
    with open(file_path, "r", encoding="utf-8") as file:
        return file.read()

def get_vectorstore(text_chunks: List[str]) -> FAISS:
    embeddings = OpenAIEmbeddings(openai_api_key=OPENAI_API_KEY)
    return FAISS.from_texts(texts=text_chunks, embedding=embeddings)

def normalize_l2(x: np.ndarray) -> np.ndarray:
    x = np.array(x)
    if x.ndim == 1:
        norm = np.linalg.norm(x)
        if norm == 0:
            return x
        return x / norm
    else:
        norm = np.linalg.norm(x, axis=1, keepdims=True)
        return np.where(norm == 0, x, x / norm)
