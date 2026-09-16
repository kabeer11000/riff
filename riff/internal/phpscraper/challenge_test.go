package phpscraper

import "testing"

// Real challenge page + cookie captured from InfinityFree during development.
// If InfinityFree changes their challenge script's argument order again, this
// is the test that should catch it.
const sampleChallenge = `<html><body><script type="text/javascript" src="/aes.js" ></script><script>function toNumbers(d){var e=[];d.replace(/(..)/g,function(d){e.push(parseInt(d,16))});return e}function toHex(){for(var d=[],d=1==arguments.length&&arguments[0].constructor==Array?arguments[0]:arguments,e="",f=0;f<d.length;f++)e+=(16>d[f]?"0":"")+d[f].toString(16);return e.toLowerCase()}var a=toNumbers("f655ba9d09a112d4968c63579db590b4"),b=toNumbers("98344c2eee86c3994890592585b49f80"),c=toNumbers("c4c77a73718eb5bb248fe400eef76eb5");document.cookie="__test="+toHex(slowAES.decrypt(c,2,a,b))+"; max-age=21600; expires=Thu, 31-Dec-37 23:55:55 GMT; path=/"; location.href="https://example.rf.gd/tests/youtube-scraper-test-1/?i=1";</script><noscript>This site requires Javascript to work, please enable Javascript in your browser or use a browser with Javascript support</noscript></body></html>`

const wantCookie = "2f312d304562ccae42675f89848424b1"

func TestIsChallenge(t *testing.T) {
	if !isChallenge(sampleChallenge) {
		t.Fatal("expected sample page to be detected as a challenge")
	}
	if isChallenge(`{"id":"abc","title":"real content"}`) {
		t.Fatal("real JSON must not be detected as a challenge")
	}
}

func TestSolveChallenge(t *testing.T) {
	got, err := solveChallenge(sampleChallenge)
	if err != nil {
		t.Fatalf("solveChallenge: %v", err)
	}
	if got != wantCookie {
		t.Fatalf("cookie = %q, want %q", got, wantCookie)
	}
}
