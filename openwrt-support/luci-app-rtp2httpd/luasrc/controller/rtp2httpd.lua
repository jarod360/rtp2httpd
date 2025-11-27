module("luci.controller.rtp2httpd", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/rtp2httpd") then
        return
    end
    
    entry({"admin", "services", "rtp2httpd"}, cbi("rtp2httpd/rtp2httpd"), _("Rtp2httpd"), 60).dependent = true
end
