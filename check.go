package main

import (
	"bufio"
	"fmt"
	"github.com/samuel/go-gettext/gettext"
	"html/template"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"sync"
	"syscall"
)

// page model
type Page struct {
	IsTor    bool
	UpToDate bool
	NotSmall bool
	OnOff    string
	Lang     string
	IP       string
	Extra    string
	Locales  map[string]string
}

type Port struct {
	min int
	max int
}

type Policy struct {
	accept bool
	ports  []Port
}

func (p Policy) CanExit(exitPort int) bool {
	if len(p.ports) == 0 {
		return false
	}
	for _, port := range p.ports {
		if port.min <= exitPort && exitPort <= port.max {
			return p.accept
		}
	}
	return !p.accept
}

var (

	// map the exit list
	// TODO: investigate other data structures
	ExitMap  map[string]Policy
	ExitLock = new(sync.RWMutex)

	// layout template
	Layout = template.New("")

	// public file server
	Phttp = http.NewServeMux()

	// locales map
	Locales = map[string]string{
		"ar":    "&#1593;&#1585;&#1576;&#1610;&#1577;&nbsp;(Arabiya)",
		"bms":   "Burmese",
		"cs":    "&#269;esky",
		"da":    "Dansk",
		"de":    "Deutsch",
		"el":    "&#917;&#955;&#955;&#951;&#957;&#953;&#954;&#940;&nbsp;(Ellinika)",
		"en_US": "English",
		"es":    "Espa&ntilde;ol",
		"et":    "Estonian",
		"fa_IR": "&#1601;&#1575;&#1585;&#1587;&#1740; (F&#257;rs&#299;)",
		"fr":    "Fran&ccedil;ais",
		"it_IT": "Italiano",
		"ja":    "&#26085;&#26412;&#35486;&nbsp;(Nihongo)",
		"nb":    "Norsk&nbsp;(Bokm&aring;l)",
		"nl":    "Nederlands",
		"pl":    "Polski",
		"pt":    "Portugu&ecirc;s",
		"pt_BR": "Portugu&ecirc;s do Brasil",
		"ro":    "Rom&acirc;n&#259;",
		"fi":    "Suomi",
		"ru":    "&#1056;&#1091;&#1089;&#1089;&#1082;&#1080;&#1081;&nbsp;(Russkij)",
		"th":    "Thai",
		"tr":    "T&uuml;rk&ccedil;e",
		"uk":    "&#1091;&#1082;&#1088;&#1072;&#1111;&#1085;&#1089;&#1100;&#1082;&#1072;&nbsp;(Ukrajins\"ka)",
		"vi":    "Vietnamese",
		"zh_CN": "&#20013;&#25991;(&#31616;)",
	}
)

func GetExits() map[string]Policy {
	ExitLock.RLock()
	defer ExitLock.RUnlock()
	return ExitMap
}

// load exit list
func LoadList() {

	file, err := os.Open("data/exit-policies")
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()

	exits := make(map[string]Policy)
	scan := bufio.NewScanner(file)
	for scan.Scan() {
		strs := strings.Fields(scan.Text())
		if len(strs) > 0 {
			policy := Policy{}
			if strs[1] == "accept" {
				policy.accept = true
			}
			ports := strings.Split(strs[2], ",")
			for _, p := range ports {
				s := strings.Split(p, "-")
				min, err := strconv.Atoi(s[0])
				if err != nil {
					log.Fatal(err)
				}
				port := Port{
					min: min,
					max: min,
				}
				if len(s) > 1 {
					port.max, err = strconv.Atoi(s[1])
					if err != nil {
						log.Fatal(err)
					}
				}
				policy.ports = append(policy.ports, port)
			}
			exits[strs[0]] = policy
		}
	}

	if err = scan.Err(); err != nil {
		log.Fatal(err)
	}

	// swap in exits
	ExitLock.Lock()
	ExitMap = exits
	ExitLock.Unlock()

}

func IsTor(remoteAddr string) bool {
	if net.ParseIP(remoteAddr).To4() == nil {
		return false
	}
	return GetExits()[remoteAddr].CanExit(443)
}

func UpToDate(r *http.Request) bool {
	if r.URL.Query().Get("uptodate") == "0" {
		return false
	}
	return true
}

func Small(r *http.Request) bool {
	if len(r.URL.Query().Get("small")) > 0 {
		return true
	}
	return false
}

// determine which language to use. default to english
func Lang(r *http.Request) string {
	lang := r.URL.Query().Get("lang")
	if len(lang) == 0 {
		lang = "en_US"
	}
	return lang
}

func RootHandler(w http.ResponseWriter, r *http.Request) {

	// serve public files
	if len(r.URL.Path) > 1 {
		Phttp.ServeHTTP(w, r)
		return
	}

	// get remote ip
	host := r.Header.Get("X-Forwarded-For")
	if len(host) == 0 {
		host, _, _ = net.SplitHostPort(r.RemoteAddr)
	}

	// determine if we're in Tor
	isTor := IsTor(host)

	// short circuit for torbutton
	if len(r.URL.Query().Get("TorButton")) > 0 {
		Layout.ExecuteTemplate(w, "torbutton.html", isTor)
		return
	}

	// string used for classes and such
	// in the template
	var onOff string
	if isTor {
		onOff = "on"
	} else {
		onOff = "off"
	}

	small := Small(r)
	upToDate := UpToDate(r)

	// querystring params
	extra := ""
	if small {
		extra += "&small=1"
	}
	if !upToDate {
		extra += "&uptodate=0"
	}

	// instance of your page model
	p := Page{
		isTor,
		isTor && !upToDate,
		!small,
		onOff,
		Lang(r),
		host,
		extra,
		Locales,
	}

	// render the template
	Layout.ExecuteTemplate(w, "index.html", p)

}

func main() {

	// determine which port to run on
	port := os.Getenv("PORT")
	if len(port) == 0 {
		port = "8000"
	}

	// load i18n
	domain, err := gettext.NewDomain("check", "locale")
	if err != nil {
		log.Fatal(err)
	}

	// add template funcs
	Layout = Layout.Funcs(template.FuncMap{
		"UnEscaped": func(x string) interface{} {
			return template.HTML(x)
		},
		"UnEscapedURL": func(x string) interface{} {
			return template.URL(x)
		},
		"GetText": func(lang string, text string) string {
			return domain.GetText(lang, text)
		},
	})

	// load layout
	Layout, err = Layout.ParseFiles(
		"public/index.html",
		"public/torbutton.html",
	)
	if err != nil {
		log.Fatal(err)
	}

	// load exits
	LoadList()

	// listen for signal to reload exits
	s := make(chan os.Signal, 1)
	signal.Notify(s, syscall.SIGUSR2)
	go func() {
		for {
			<-s
			LoadList()
			log.Println("Exit list reloaded.")
		}
	}()

	// routes
	http.HandleFunc("/", RootHandler)

	// files
	files := http.FileServer(http.Dir("./public"))
	Phttp.Handle("/torcheck/", http.StripPrefix("/torcheck/", files))
	Phttp.Handle("/", files)

	// start the server
	log.Printf("Listening on port: %s\n", port)
	log.Fatal(http.ListenAndServe(fmt.Sprintf(":%s", port), nil))

}
