window = this;
global = this;

window.screen = {};
window._gl = {};
window.performance = {};
window.browser = {};
window.EXOKIT = {};
EXOKIT._emptyBuffer = {_id: 0};
EXOKIT._emptyTexture = {_id: 0};
EXOKIT._emptyVertexArray = {_id: 0};
EXOKIT._emptyFrameBuffer = {_id: 1}; //Important!
EXOKIT._emptyRenderBuffer = {_id: 2};

EXOKIT._img = {'_src': '-1'};

(function() {
    let console = window.console;
    window.console = {
      log: function(c) {
        print("LOG :: " +(typeof c === 'object' ? JSON.stringify(c) : c));
        console.log(c);
      },

      warn: function(c, d) {
        print("WARN :: " + c + " " + d);
        console.warn(c, d);
      },

      error: function(c, d) {
        print("ERROR :: " + c + d);
        console.error(c, d);
      },

      trace: function(c) {
        let e = new Error();
        print("TRACE :: " + e.toString());
        console.trace();
      }
    };
})();

console.time = function() {
    console._saveTime = performance.now();
}

console.timeEnd = function() {
    console.log(performance.now() - console._saveTime);
}

window.Image = function() { };
Image.prototype = {
	set src (val) {
		this._src = val;
		var dim = _gl._getImageDimensions(val);
		this.width = dim[0];
		this.height = dim[1];
		this.complete = true;
        let _this = this;
        setTimeout(() => _this.onload && _this.onload(), 10);
	},
	get src() {
		return this._src;
	}
};