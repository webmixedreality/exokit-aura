const {PlaneGeometry, Renderer, Shader, FBO, Matrix4, Vector3, Vector2, Quaternion, Euler, Group, PerspectiveCamera} = require('exokitgl');
const {Camera} = require('./camera');
const shaders = require('./camera-shaders');

var _camera;

let renderer = new Renderer();
let rotation = new Euler();
let cameraGroup = new Group();
let quaternion = new Quaternion();
let euler = new Euler();
let camera = new PerspectiveCamera(35, 1, 0.1, 1000);

function radians(degrees) {
    return degrees * (Math.PI / 180);
}

window.EXOKIT_AR = {};
EXOKIT_AR.setTrackingOrientation = function(orientation) {
    if (_camera) _camera.orientation = orientation;

    switch (orientation) {
        case 'portrait': euler.z = radians(90); break;
        case 'portraitUpsideDown': euler.z = radians(-90); break;
        case 'landscapeLeft': euler.z = 0; break;
        case 'landscapeRight': euler.z = radians(180); break;
    }

    quaternion.setFromEuler(euler);
};

EXOKIT_AR.setProjectionMatrix = _ => {};

EXOKIT_AR.setRotation = function(value) {
    rotation.fromArray(value);
};

EXOKIT_AR.setTransform = function(value) {
    camera.matrixWorld.fromArray(value);
    camera.matrixWorld.decompose(camera.position, camera.quaternion, camera.scale);
    camera.quaternion.multiply(quaternion);
    camera.updateMatrixWorld();
    EXOKIT_AR.onUpdatePose && EXOKIT_AR.onUpdatePose(camera);
};

EXOKIT_AR.setLightIntensity = function() {

};

EXOKIT_AR.setTrackingState = function() {

};

require('./api');

function blit(from, to) {
    let gl = _gl;
    gl.bindFramebuffer(gl.READ_FRAMEBUFFER, from._gl);
    gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, to ? to._gl : null);
    gl.blitFramebuffer(0, 0, from.width, from.height, 0, 0, to ? to.width : _camera.fbo.width, to ? to.height : _camera.fbo.height, gl.COLOR_BUFFER_BIT, gl.LINEAR);
    gl.bindFramebuffer(gl.READ_FRAMEBUFFER, null);
    gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, null);
}

let copyShader, copyGeom;
function drawCameraToFBO() {
    if (!copyShader) {
        copyShader = new Shader(shaders.vs, shaders.copy, {
            tMap: {type: 't', value: _camera.texture}
        });
        copyGeom = new PlaneGeometry(2, 2);
    }

    _gl.bindFramebuffer(_gl.FRAMEBUFFER, EXOKIT_AR.FBO._gl);
    renderer.draw(copyShader, copyGeom);
    _gl.clear(_gl.DEPTH_BUFFER_BIT);
    _gl.bindFramebuffer(_gl.FRAMEBUFFER, null);
}

EXOKIT_AR.init = function() {
    _camera = new Camera();

    window.requestAnimationFrame = function() {

    };

    EXOKIT.animationFrame = function() {
        if (!EXOKIT_AR.FBO) return;
        _camera.draw();
        drawCameraToFBO();
        EXOKIT_AR.onAnimationFrame && EXOKIT_AR.onAnimationFrame();
        blit(EXOKIT_AR.FBO, null);
    }

    EXOKIT_AR.interface = ARInterface.create();
}
