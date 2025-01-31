package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path"
)

func main() {

	// command line args
	logPath := flag.String("log", "", "path to log file; otherwise stdout")
	pidPath := flag.String("pid", "./check.pid", "path to create pid")
	basePath := flag.String("base", "./", "path to base dir")
	port := flag.Int("port", 8000, "port to listen on")
	flag.Parse()

	// log to file
	if len(*logPath) > 0 {
		f, err := os.Create(*logPath)
		if err != nil {
			log.Fatal(err)
		}
		log.SetOutput(f)
	}

	// write pid
	pid, err := os.Create(*pidPath)
	if err != nil {
		log.Fatal(err)
	}
	if _, err = fmt.Fprintf(pid, "%d\n", os.Getpid()); err != nil {
		log.Fatal(err)
	}
	if err = pid.Close(); err != nil {
		log.Fatal(err)
	}

	// Load Anon exits and listen for SIGUSR2 to reload
	exits := new(Exits)
	exits.Run(path.Join(*basePath, "data/exit-policies"))

	// files
	files := http.FileServer(http.Dir(path.Join(*basePath, "public")))
	Phttp := http.NewServeMux()
	// TODO - Unused routes are disabled. Enable them if needed.
	//Phttp.Handle("/torcheck/", http.StripPrefix("/torcheck/", files))
	Phttp.Handle("/", files)

	// routes
	http.HandleFunc("/", enableCORS(RootHandler(CompileTemplate(*basePath, "index.html"), exits, Phttp)))
	bulk := enableCORS(BulkHandler(CompileTemplate(*basePath, "bulk.html"), exits))
	http.HandleFunc("/anonbulkexitlist", bulk)
	//http.HandleFunc("/cgi-bin/TorBulkExitList.py", bulk)
	http.HandleFunc("/api/bulk", bulk)
	http.HandleFunc("/api/ip", enableCORS(APIHandler(exits)))

	// start the server
	log.Printf("Listening on port: %d\n", *port)
	log.Fatal(http.ListenAndServe(fmt.Sprintf(":%d", *port), nil))

}

func enableCORS(handler http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*") // Allow all origins
		handler(w, r)                                      // Call the original handler
	}
}
