// Hand-drawn art style: the scene is rendered off-screen, then redrawn on "paper"
// with wobbly ink outlines, pencil hatching in the shadows and slightly flattened colour.
import * as THREE from 'three';

const VERT = 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }';
const FRAG = `
uniform sampler2D tColor, tDepth, tPaper;
uniform vec2 res; uniform float near, far, time, exposure, px;
varying vec2 vUv;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p){ vec2 i = floor(p), f = fract(p); f = f*f*(3.0-2.0*f);
  return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y); }
float viewZ(vec2 uv){ float d = texture2D(tDepth, uv).r * 2.0 - 1.0; return 2.0*near*far / (far + near - d*(far - near)); }
float lum(vec3 c){ return dot(c, vec3(0.299, 0.587, 0.114)); }
vec3 skRRT(vec3 v){ vec3 a = v*(v + 0.0245786) - 0.000090537; vec3 b = v*(0.983729*v + 0.4329510) + 0.238081; return a/b; }
vec3 skAces(vec3 c){
  const mat3 I = mat3(vec3(0.59719,0.07600,0.02840), vec3(0.35458,0.90834,0.13383), vec3(0.04823,0.01566,0.83777));
  const mat3 O = mat3(vec3(1.60475,-0.10208,-0.00327), vec3(-0.53108,1.10813,-0.07276), vec3(-0.07367,-0.00605,1.07602));
  c *= exposure / 0.6; return clamp(O * skRRT(I * c), 0.0, 1.0);
}
vec3 shade(vec2 uv){ return pow(skAces(texture2D(tColor, uv).rgb), vec3(1.0/2.2)); }

void main(){
  // the whole drawing wobbles a little, redrawn a few times a second like animation cels
  vec2 w = vec2(noise(vUv*7.0 + time*3.1), noise(vUv*7.0 - time*2.3 + 5.2)) - 0.5;
  vec2 uv = vUv + w * 2.2 * px / res;
  vec3 c = shade(uv);

  // ink: creases and silhouettes from depth, plus strong colour changes
  vec2 o = px * 1.25 / res;
  float z0 = viewZ(uv), zl = viewZ(uv - vec2(o.x,0.0)), zr = viewZ(uv + vec2(o.x,0.0)), zd = viewZ(uv - vec2(0.0,o.y)), zu = viewZ(uv + vec2(0.0,o.y));
  float crease = (abs(zl + zr - 2.0*z0) + abs(zd + zu - 2.0*z0)) / z0;
  float jump = max(max(abs(zl - z0), abs(zr - z0)), max(abs(zd - z0), abs(zu - z0))) / z0;
  float l0 = lum(c);
  float lc = abs(lum(shade(uv - vec2(o.x,0.0))) + lum(shade(uv + vec2(o.x,0.0))) + lum(shade(uv - vec2(0.0,o.y))) + lum(shade(uv + vec2(0.0,o.y))) - 4.0*l0);
  float fade = 1.0 - smoothstep(250.0, 900.0, z0);                       // lighter lines far away
  float ink = max(smoothstep(0.012, 0.04, crease), smoothstep(0.06, 0.16, jump));
  ink = max(ink, smoothstep(0.22, 0.5, lc) * 0.7) * (0.55 + 0.45 * fade);
  ink *= 0.75 + 0.5 * noise(gl_FragCoord.xy * 0.35 + time * 9.0);       // a pencil's uneven pressure

  // flatter, watercolour-ish colour
  vec3 post = floor(c * 7.0 + 0.5) / 7.0;
  c = mix(c, post, 0.4);
  c = mix(vec3(l0), c, 0.88) * vec3(1.04, 1.0, 0.92);
  c = mix(c, vec3(1.0), 0.12);

  // hatching where it's dark, cross-hatching where it's darker
  vec2 sp = gl_FragCoord.xy / px + w * 8.0;
  float h1 = 1.0 - smoothstep(0.06, 0.2, abs(fract((sp.x + sp.y) / 6.5) - 0.5));
  float h2 = 1.0 - smoothstep(0.06, 0.2, abs(fract((sp.x - sp.y) / 7.5) - 0.5));
  float dark = 1.0 - l0;
  float hatch = h1 * smoothstep(0.58, 0.8, dark) + h2 * smoothstep(0.72, 0.9, dark);
  c *= 1.0 - hatch * 0.28;

  // paper grain, then the ink on top
  vec3 paper = texture2D(tPaper, gl_FragCoord.xy / (512.0 * px)).rgb;
  c *= paper;
  c = mix(c, vec3(0.16, 0.12, 0.1), clamp(ink, 0.0, 1.0) * 0.85);
  float vig = 1.0 - dot(vUv - 0.5, vUv - 0.5) * 0.5;
  gl_FragColor = vec4(pow(c * vig, vec3(2.2)), 1.0);
  #include <colorspace_fragment>
}`;

function paperTexture() {
  const N = 512, cv = document.createElement('canvas'); cv.width = cv.height = N;
  const x = cv.getContext('2d');
  x.fillStyle = '#fbf6ea'; x.fillRect(0, 0, N, N);
  const img = x.getImageData(0, 0, N, N);
  for (let i = 0; i < N * N; i++) {
    const v = (Math.random() - 0.5) * 14;
    img.data[i * 4] += v; img.data[i * 4 + 1] += v; img.data[i * 4 + 2] += v * 0.9;
  }
  x.putImageData(img, 0, 0);
  // fibres and soft blotches
  for (let k = 0; k < 500; k++) {
    x.strokeStyle = `rgba(120,100,70,${0.03 + Math.random() * 0.05})`; x.lineWidth = 0.6;
    const a = Math.random() * N, b = Math.random() * N, t = Math.random() * 6.28, l = 4 + Math.random() * 14;
    x.beginPath(); x.moveTo(a, b); x.quadraticCurveTo(a + Math.cos(t) * l, b + Math.sin(t) * l, a + Math.cos(t + 0.5) * l * 1.6, b + Math.sin(t + 0.5) * l * 1.6); x.stroke();
  }
  for (let k = 0; k < 40; k++) {
    const g = x.createRadialGradient(0, 0, 0, 0, 0, 30 + Math.random() * 60);
    g.addColorStop(0, 'rgba(170,140,90,0.05)'); g.addColorStop(1, 'rgba(170,140,90,0)');
    x.save(); x.translate(Math.random() * N, Math.random() * N); x.fillStyle = g; x.fillRect(-90, -90, 180, 180); x.restore();
  }
  const t = new THREE.CanvasTexture(cv); t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}

export function createSketch(renderer) {
  const size = new THREE.Vector2();
  renderer.getDrawingBufferSize(size);
  const rt = new THREE.WebGLRenderTarget(size.x, size.y, { type: THREE.HalfFloatType });
  rt.depthTexture = new THREE.DepthTexture(size.x, size.y);
  const material = new THREE.ShaderMaterial({
    vertexShader: VERT, fragmentShader: FRAG, depthTest: false, depthWrite: false,
    uniforms: {
      tColor: { value: rt.texture }, tDepth: { value: rt.depthTexture }, tPaper: { value: paperTexture() },
      res: { value: size.clone() }, near: { value: 0.5 }, far: { value: 5000 }, time: { value: 0 }, exposure: { value: 0.6 }, px: { value: renderer.getPixelRatio() },
    },
  });
  const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), material);
  quad.frustumCulled = false;
  const quadScene = new THREE.Scene(); quadScene.add(quad);
  const quadCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  let clock = 0;
  return {
    render(scene, camera, dt) {
      clock += dt;
      const u = material.uniforms;
      u.time.value = Math.floor(clock * 4) / 4;          // re-"drawn" four times a second
      u.near.value = camera.near; u.far.value = camera.far; u.exposure.value = renderer.toneMappingExposure;
      renderer.setRenderTarget(rt);
      renderer.render(scene, camera);
      renderer.setRenderTarget(null);
      renderer.render(quadScene, quadCam);
    },
    setSize() {
      renderer.getDrawingBufferSize(size);
      rt.setSize(size.x, size.y);
      material.uniforms.res.value.copy(size);
      material.uniforms.px.value = renderer.getPixelRatio();
    },
  };
}
