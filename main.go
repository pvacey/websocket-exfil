package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"text/template"

	"github.com/gorilla/websocket"
)

var baseDir = "uploads"

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
}

type Message struct {
	FileName string `json:"filename"`
}

func tarpitMiddleware(next http.Handler) http.Handler {
	//TODO:
	// - create a random 6 digit code that must be in the path,tarpit the request if it is not present
	// - keep rotating the code every time it is requested once
	// - log the request with the code and the user agent
	// - somehow provide this code to the backend user out of band
	// - maybe make sure the template is served only once, so the user has to request it again to get a new code for each WebSocket connection

	// intercept requests that do not come from Windows PowerShell, make them wait indefinitely
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		userAgent := r.UserAgent()
		if userAgent == "" {
			userAgent = r.Header.Get("X-User-Agent")
		}
		if !strings.Contains(userAgent, "WindowsPowerShell") {
			w.(http.Hijacker).Hijack()
			log.Printf("Tarpitting request from %s with User-Agent: %s", r.RemoteAddr, userAgent)
			return
		}
		log.Printf("Allowing request from %s with User-Agent: %s", r.RemoteAddr, userAgent)
		next.ServeHTTP(w, r)
	})
}

func handleHomepage(w http.ResponseWriter, r *http.Request) {
	// Serve the client template for PowerShell upload script
	var tmplFile = "client.ps1"
	tmpl, err := template.New(tmplFile).ParseFiles(tmplFile)
	if err != nil {
		panic(err)
	}
	err = tmpl.Execute(w, r)
	if err != nil {
		panic(err)
	}
}

func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	// upgrade the HTTP connection to a WebSocket connection
	// log.Printf("Allowing websocket request from %s with User-Agent: %s", r.RemoteAddr, r.Header.Get("X-User-Agent"))
	upgrader.CheckOrigin = func(r *http.Request) bool { return true }
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Println(err)
		return
	}
	// start the WebSocket loop to handle incoming messages from this connection
	go webSocketLoop(conn)
}

func webSocketLoop(conn *websocket.Conn) {
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
			log.Printf("Incoming file '%s' from %s", message.FileName, conn.RemoteAddr().String())
		} else if messageType == websocket.BinaryMessage {
			log.Printf("Received binary data for file'%s' from %s", message.FileName, conn.RemoteAddr().String())
			err := saveFile(message.FileName, msg)
			if err != nil {
				log.Fatal(err)
			}
		}
	}
}

func saveFile(fileName string, data []byte) error {
	// prevent directory traversal attacks
	baseFileName := filepath.Base(fileName)
	fullFileName := filepath.Join(baseDir, baseFileName)

	return os.WriteFile(fullFileName, data, 0644)
}

func uploadListener(port int) {
	if _, err := os.Stat(baseDir); os.IsNotExist(err) {
		os.Mkdir(baseDir, 0755)
	}

	http.Handle("/", tarpitMiddleware(http.HandlerFunc(handleHomepage)))
	http.Handle("/ws", tarpitMiddleware(http.HandlerFunc(handleWebSocket)))
	// http.Handle("/ws", http.HandlerFunc(handleWebSocket))
	log.Printf("Running upload mode on port %d, files will be saved to '%s'", port, baseDir)
	log.Fatal(http.ListenAndServe(fmt.Sprintf(":%d", port), nil))
}

func downloadListner(port int) {
	fs := http.FileServer(http.Dir(baseDir))
	http.Handle("/", fs)
	log.Printf("Running download mode on port %d, serving files from '%s'", port, baseDir)
	log.Fatal(http.ListenAndServe(fmt.Sprintf(":%d", port), nil))
}

func main() {
	if _, err := os.Stat(baseDir); os.IsNotExist(err) {
		os.Mkdir(baseDir, 0755)
	}

	portPtr := flag.Int("port", 8080, "specify the port to run the server on")
	modePtr := flag.String("mode", "upload", "specify the mode: upload or download")
	flag.Parse()

	switch *modePtr {
	case "upload":
		uploadListener(*portPtr)
	case "download":
		downloadListner(*portPtr)
	default:
		flag.Usage()
		os.Exit(1)
	}
}
