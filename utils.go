package main

import (
	"fmt"
	"html/template"
	"log"
	"net"
	"net/http"
	"net/url"
	"path"
	"regexp"
	"strconv"
	"strings"
)

func IsParamSet(r *http.Request, param string) bool {
	return len(r.URL.Query().Get(param)) > 0
}

func Lang(r *http.Request) string {
	lang := r.URL.Query().Get("lang")
	if len(lang) == 0 {
		lang = "en_US"
	}
	return lang
}

func GetQS(q url.Values, param string, deflt int) (num int, str string) {
	str = q.Get(param)
	num, err := strconv.Atoi(str)
	if err != nil {
		num = deflt
		str = ""
	} else {
		str = fmt.Sprintf("&%s=%s", param, str)
	}
	return
}

func GetHost(r *http.Request) (host string, err error) {
	// get remote ip
	host = r.Header.Get("X-Forwarded-For")
	if len(host) > 0 {
		parts := strings.Split(host, ",")
		// apache will append the remote address
		host = strings.TrimSpace(parts[len(parts)-1])
	} else {
		host, _, err = net.SplitHostPort(r.RemoteAddr)
	}
	return
}

var TBBUserAgents = regexp.MustCompile(`^Mozilla/5\.0 \([^)]*\) Gecko/([\d]+\.0|20100101) Firefox/[\d]+\.0$`)

func LikelyTBB(ua string) bool {
	return TBBUserAgents.MatchString(ua)
}

var Layout *template.Template

func CompileTemplate(base string, templateName string) *template.Template {
	if Layout == nil {
		Layout = template.New("")
		Layout = template.Must(Layout.ParseFiles(
			path.Join(base, "public/base.html"),
		))
	}
	l, err := Layout.Clone()
	if err != nil {
		log.Fatal(err)
	}
	return template.Must(l.ParseFiles(path.Join(base, "public/", templateName)))
}
