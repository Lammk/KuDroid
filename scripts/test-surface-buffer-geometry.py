#!/usr/bin/env python3
"""Check buffer size and presentation geometry against driver resize calculations."""

from pathlib import Path
import argparse
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', type=Path, default=ROOT / 'src/platform/graphics/NativeWindows.inc')
SOURCE = parser.parse_args().source.read_text(encoding='utf-8')
START = SOURCE.index('static void render_layer_sync_geometry(')
END = SOURCE.index('// Main thread only.', START)
FUNCTION = SOURCE[START:END]
FUNCTION = re.sub(r'auto (\w+) = reinterpret_cast<[^>]+>\(objc_msgSend\);',
                  lambda match: 'auto ' + match[1] + ' = fake_' + match[1] + ';', FUNCTION)
HARNESS = r'''
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <unordered_map>
struct CGPoint { double x, y; };
struct CGSize { double width, height; };
struct CGRect { CGPoint origin; CGSize size; };
struct CGAffineTransform { double a, b, c, d, tx, ty; };
static CGRect CGRectMake(double x, double y, double w, double h) { return {{x,y},{w,h}}; }
static CGPoint CGPointMake(double x, double y) { return {x,y}; }
static CGSize CGSizeMake(double w, double h) { return {w,h}; }
static CGAffineTransform CGAffineTransformMakeScale(double x, double y) { return {x,0,0,y,0,0}; }
struct Layer {
    CGRect bounds{{0,0},{800,400}};
    double scale = 2;
    CGSize drawable{0,0};
    CGPoint position{0,0};
    CGAffineTransform transform{1,0,0,1,0,0};
};
using id = Layer*;
using Class = Layer*;
using SEL = const char*;
using BOOL = bool;
static constexpr BOOL YES = true;
static SEL sel_registerName(const char* name) { return name; }
static Class objc_getClass(const char*) { return nullptr; }
static CGRect fake_getRect(id layer, SEL) { return layer->bounds; }
static double fake_getFloat(id layer, SEL) { return layer->scale; }
static void fake_setRect(id layer, SEL selector, CGRect rect) {
    layer->bounds = rect;
    if (std::strcmp(selector,"setFrame:") == 0) {
        layer->position = {rect.origin.x + rect.size.width/2, rect.origin.y + rect.size.height/2};
    }
}
static void fake_setFloat(id layer, SEL, double scale) { layer->scale = scale; }
static void fake_setSize(id layer, SEL, CGSize size) { layer->drawable = size; }
static void fake_setPoint(id layer, SEL, CGPoint point) { layer->position = point; }
static void fake_setTransform(id layer, SEL, CGAffineTransform transform) { layer->transform = transform; }
static void fake_voidCall(id, SEL) {}
static void fake_setBool(id, SEL, BOOL) {}
struct SurfaceFrame {
    std::mutex mutex;
    int x=0, y=0, width=0, height=0, bufferWidth=0, bufferHeight=0;
};
static std::mutex g_surfaceLayersMtx;
static std::unordered_map<void*,std::shared_ptr<SurfaceFrame>> g_layerFrames;
static std::unordered_map<void*,void*> g_presentationLayers;
'''
CHECKS = r'''
static int failures = 0;
static void check(bool ok, const char* label) {
    std::printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}
static bool near(double a, double b) { return std::abs(a-b) < 0.000001; }
static CGSize driverSize(const Layer& layer) {
    return {layer.bounds.size.width * layer.scale, layer.bounds.size.height * layer.scale};
}
int main() {
    Layer host, child, presentation;
    auto frame = std::make_shared<SurfaceFrame>();
    frame->x=20; frame->y=30; frame->width=1200; frame->height=600;
    frame->bufferWidth=1600; frame->bufferHeight=900;
    g_layerFrames[&child]=frame;
    g_presentationLayers[&child]=&presentation;
    render_layer_sync_geometry(&child,&host,1600,800,2);
    auto size=driverSize(child);
    check(near(size.width,1600) && near(size.height,900), "driver resize preserves explicit buffer dimensions");
    check(near(child.drawable.width,size.width) && near(child.drawable.height,size.height),
          "drawable size agrees with driver bounds and scale");
    check(near(child.transform.a,1) && near(child.transform.d,1), "renderer frame also preserves buffer dimensions");
    check(near(presentation.bounds.size.width*presentation.transform.a*child.scale,1200) &&
          near(presentation.bounds.size.height*presentation.transform.d*child.scale,600), "presentation retains view dimensions");
    check(near(presentation.position.x*child.scale,620) && near(presentation.position.y*child.scale,330),
          "presentation retains view position");
    host.scale=3;
    render_layer_sync_geometry(&child,&host,1600,800,3);
    size=driverSize(child);
    check(near(size.width,1600) && near(size.height,900), "density change preserves selected buffer size");
    frame->bufferWidth=0; frame->bufferHeight=0;
    render_layer_sync_geometry(&child,&host,1600,800,3);
    size=driverSize(child);
    check(near(size.width,1200) && near(size.height,600), "zero geometry follows view dimensions");
    check(near(child.transform.a,1) && near(child.transform.d,1), "zero geometry restores identity transform");
    frame->width=600; frame->height=1200;
    render_layer_sync_geometry(&child,&host,800,1600,3);
    size=driverSize(child);
    check(near(size.width,600) && near(size.height,1200), "layout-driven buffers follow rotation");
    g_layerFrames.clear();
    g_presentationLayers.clear();
    render_layer_sync_geometry(&child,&host,1600,800,3);
    size=driverSize(child);
    check(near(size.width,2400) && near(size.height,1200), "unframed surfaces follow host bounds");
    host.bounds.size={0,0};
    render_layer_sync_geometry(&child,&host,800,600,3);
    size=driverSize(child);
    check(near(size.width,800) && near(size.height,600), "initial layout uses supplied surface dimensions");
    return failures ? 1 : 0;
}
'''
with tempfile.TemporaryDirectory(prefix='surface-buffer-geometry-') as directory:
    source = Path(directory) / 'geometry.cpp'
    binary = Path(directory) / 'geometry'
    source.write_text(HARNESS + FUNCTION + CHECKS, encoding='utf-8')
    subprocess.run(['c++', '-std=c++17', '-pthread', str(source), '-o', str(binary)], check=True, timeout=120)
    subprocess.run([str(binary)], check=True, timeout=30)
