REPO=kubernetes.lan:30500
APP=websocket_exfil
TAG=$(shell TZ='America/Chicago' date +%m%d%Y_%H%m%S)
LATEST_ID=$(shell docker images ${APP} --format "{{.Repository}}:{{.Tag}} {{.ID}}" | grep "latest" | awk '{print $$2}')

build:
	@echo "[*] Building Docker image for ${APP} with tag ${TAG}"
	docker build -t ${APP}:${TAG} .
	@echo "[*] Tagging Docker image ${APP}:${TAG} as latest"
	docker tag ${APP}:${TAG} ${APP}:latest
	@echo "[*] Listing Docker images for ${APP}"
	docker image ls ${APP}

build-tunnel:
	@echo "[*] Building Docker image for cftunnel with tag ${TAG}"
	docker build -f Dockerfile.tunnel -t cftunnel:${TAG} .
	@echo "[*] Tagging Docker image cftunnel:${TAG} as latest"
	docker tag cftunnel:${TAG} cftunnel:latest
	@echo "[*] Listing Docker images for cftunnel"
	docker image ls cftunnel

run:
	@echo "[*] Running Docker container for ${APP} on port 8080"
	docker run -p 8080:8080 ${APP}:latest

push:
	@echo "[*] Pushing Docker image ${APP}:latest to ${REPO}"
	docker tag ${APP}:latest ${REPO}/${APP}:latest
	docker push ${REPO}/${APP}:latest

push-tunnel:
	@echo "[*] Pushing Docker image cftunnel:latest to ${REPO}"
	docker tag cftunnel:latest ${REPO}/cftunnel:latest
	docker push ${REPO}/cftunnel:latest

clean:
	@echo "[*] Removing all stopped containers"
	docker rm $(shell docker ps -aq) || true
	@echo "[*] Removing all Docker images for ${APP} except the latest"
	docker image ls --format "{{.Repository}} {{.ID}}" | grep ${APP} | grep -v ${LATEST_ID} | awk '{print $$2}' | xargs -r docker rmi -f
	@echo "[*] Pruning unused Docker images"
	docker image prune -f

clean-tunnel:
	@echo "[*] Removing all stopped containers"
	docker rm $(shell docker ps -aq) || true
	@echo "[*] Removing all Docker images for ${APP} except the latest"
	docker image ls --format "{{.Repository}} {{.ID}}" | grep ${APP} | grep -v ${LATEST_ID} | awk '{print $$2}' | xargs -r docker rmi -f
	@echo "[*] Pruning unused Docker images"
	docker image prune -f

