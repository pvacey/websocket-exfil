import asyncio
import json
import logging
import websockets

def create_logger(name):
    logger = logging.getLogger(name)
    logger.setLevel(logging.DEBUG)

    formatter = logging.Formatter('[%(asctime)s] [%(levelname)s] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')

    handler = logging.StreamHandler()
    handler.setFormatter(formatter)
    logger.addHandler(handler)

    return logger


async def echo(websocket):
    filename = ''
    async for message in websocket:
        if type(message) == str:
            filename = json.loads(message).get('filename')
            logger.info(f"Incoming file: {filename}")
        else:
            logger.info(f"Receiving data: {filename}")
            with open(filename, 'wb') as f:
                f.write(message)
            logger.info(f"File Complete: {filename}")

async def main():    
    async with websockets.serve(echo, "localhost", 8765):
        logger.info("WebSocket server started at ws://localhost:8765")
        await asyncio.Future()  # Keep the server running

if __name__ == "__main__":
    
    logger = create_logger(__file__)
    asyncio.run(main()) 