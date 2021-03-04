#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

#include "./shader.h"

typedef void zig_log(char* str);

static CVReturn renderCallback(CVDisplayLinkRef displayLink,
        const CVTimeStamp *inNow,
        const CVTimeStamp *inOutputTime,
        CVOptionFlags flagsIn,
        CVOptionFlags *flagsOut,
        void *displayLinkContext
);

void perspective(float *out, float fov, float aspect, float near, float far) {
    float fov_rad = fov * M_PI / 180.0f;
    float f = 1.0f / tan(fov_rad / 2.0f);
    float range_inv = 1.0f / (near - far);

    out[0] = f / aspect;
    out[1] = 0;
    out[2] = 0;
    out[3] = 0;

    out[4] = 0;
    out[5] = f;
    out[6] = 0;
    out[7] = 0;

    out[8] = 0;
    out[9] = 0;
    out[10] = (near + far) * range_inv;
    out[11] = -1.0f;

    out[12] = 0;
    out[13] = 0;
    out[14] = near * far * range_inv * 2;
    out[15] = 0;
}

void multiply(float *out, float const *a, float const *b) {
    for (int i = 0; i < 16; i++) {
        int row = floor(i / 4);
        int column = i % 4;

        out[i] = a[column] * b[row * 4]
            + a[column + 4] * b[ row * 4 + 1]
            + a[column + 8] * b[row * 4 + 2]
            + a[column + 12] * b[row * 4 + 3];
    }
}

void rotateZ(float *out, float angle) {
    out[0] = cos(angle);
    out[1] = -sin(angle);
    out[2] = 0;
    out[3] = 0;

    out[4] = sin(angle);
    out[5] = cos(angle);
    out[6] = 0;
    out[7] = 0;

    out[8] = 0;
    out[9] = 0;
    out[10] = 1;
    out[11] = 0;

    out[12] = 0;
    out[13] = 0;
    out[14] = 0;
    out[15] = 1;
}

void rotateY(float *out, float angle) {
    out[0] = cos(angle);
    out[1] = 0;
    out[2] = -sin(angle);
    out[3] = 0;

    out[4] = 0;
    out[5] = 1;
    out[6] = 0;
    out[7] = 0;

    out[8] = sin(angle);
    out[9] = 0;
    out[10] = cos(angle);
    out[11] = 0;

    out[12] = 0;
    out[13] = 0;
    out[14] = 0;
    out[15] = 1;
}

void translate(float *out, float x, float y, float z) {
    out[0] = 1;
    out[1] = 0;
    out[2] = 0;
    out[3] = 0;

    out[4] = 0;
    out[5] = 1;
    out[6] = 0;
    out[7] = 0;

    out[8] = 0;
    out[9] = 0;
    out[10] = 1;
    out[11] = 0;

    out[12] = x;
    out[13] = y;
    out[14] = z;
    out[15] = 1;
}

@interface Renderer : NSObject {
    CVDisplayLinkRef displayLink;
    struct Uniforms uniforms;
    @public zig_log* log_debug;
}
@property (nonatomic, strong) CAMetalLayer *layer;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) NSView *currentView;

@property (nonatomic, strong) id<MTLBuffer> positionBuffer;
@property (nonatomic, strong) id<MTLBuffer> indexBuffer;
@property (nonatomic, strong) id<MTLBuffer> sampleBuffer;

@property (nonatomic, strong) id<MTLRenderPipelineState> pipeline;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;

@property (readwrite) CVDisplayLinkRef displayLink;

@property size_t write_head;
@property size_t point_vertices;
@end

@implementation Renderer
@synthesize displayLink;

-(void) setup:(char *)vst_path {
    self.layer = [CAMetalLayer layer];
    self.layer.device = MTLCreateSystemDefaultDevice();
    self.layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    self.currentView = NULL;
    self.device = self.layer.device;
    self.point_vertices = 10;

    uniforms.num_frames = pow(2, 8);
    uniforms.point_scale = 0.01;
    uniforms.graph_scale = 1.0;


    for (int i = 0; i < 16; i++) {
        NSLog(@"%f", uniforms.matrix[i]);
    }

    CGDirectDisplayID displayId = CGMainDisplayID();
    CVReturn error = kCVReturnSuccess;

    error = CVDisplayLinkCreateWithCGDisplay(displayId, &displayLink);

    if (error) {
        NSLog(@"CVDisplayLink setup failed");
    }

    CVDisplayLinkSetOutputCallback(displayLink, renderCallback, (__bridge void *)self);

    [self bufferSetup];
    [self pipelineSetup:vst_path];
}

-(void) bufferSetup {
    size_t byte_size = sizeof(float) * (self.point_vertices + 1) * 3;
    self.positionBuffer = [self.device newBufferWithLength:byte_size options:MTLResourceOptionCPUCacheModeDefault];
    float *position_buf = self.positionBuffer.contents;

    size_t index_byte_size = sizeof(uint16_t) * (self.point_vertices) * 3;
    self.indexBuffer = [self.device newBufferWithLength:index_byte_size options:MTLResourceOptionCPUCacheModeDefault];
    uint16_t *index_buf = self.indexBuffer.contents;

    position_buf[0] = 0;
    position_buf[1] = 0;
    position_buf[2] = 0;

    for (int i = 0; i < self.point_vertices; i++) {
        float angle = (float) i / (float) self.point_vertices * M_PI * 2;

        int w = i + 1;
        position_buf[w * 3] = cos(angle);
        position_buf[w * 3 + 1] = sin(angle);
        position_buf[w * 3 + 2] = 0;

        index_buf[i * 3] = 0;
        index_buf[i * 3 + 1] = i + 1;

        // Last iteration
        if (i == self.point_vertices - 1) {
            index_buf[i * 3 + 2] = 1;
        } else {
            index_buf[i * 3 + 2] = i + 2;
        }
    }

    size_t buffer_size = uniforms.num_frames * 2 * sizeof(float);
    self.sampleBuffer = [self.device newBufferWithLength:buffer_size options:MTLResourceOptionCPUCacheModeWriteCombined];
}

-(void) pipelineSetup:(char *)vst_path {
    char *metal_path = malloc(4096);

    if (sprintf(metal_path, "%s/%s", vst_path, "zig-analyzer.metallib") < 0) {
        NSLog(@"Failed to build metal shader path");
        return;
    }

    NSString *metal_ns_path = [NSString stringWithUTF8String:metal_path];
    NSError *loadError = NULL;
    id<MTLLibrary> mtllib = [self.device newLibraryWithFile:metal_ns_path error:&loadError];
    free(metal_path);

    if (loadError) {
        NSLog(@"Failed to load .metallib");
        return;
    }

    id<MTLFunction> vertexFunc = [mtllib newFunctionWithName:@"vertex_main"];
    id<MTLFunction> fragmentFunc = [mtllib newFunctionWithName:@"fragment_main"];

    MTLRenderPipelineDescriptor *pipelineDescriptor = [MTLRenderPipelineDescriptor new];
    pipelineDescriptor.vertexFunction = vertexFunc;
    pipelineDescriptor.fragmentFunction = fragmentFunc;
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.layer.pixelFormat;

    self.pipeline = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:NULL];

    if (!self.pipeline) {
        NSLog(@"Failed to create pipeline");
        return;
    }

    self.commandQueue = [self.device newCommandQueue];
}

-(void) updateBuffer:(float*)ptr len:(uintptr_t)len {
    float* buf_ptr = self.sampleBuffer.contents;

    for (int i = 0; i < len; i++) {
        buf_ptr[self.write_head] = ptr[i];
        self.write_head = (self.write_head + 1) & (uniforms.num_frames * 2 - 1);
        uniforms.offset = self.write_head;
    }
}

-(void) updateMatrix {
    static float projection[16] = {0};
    static float z_rotation[16] = {0};
    static float y_rotation[16] = {0};
    static float translation[16] = {0};

    static float wrkmem[16] = {0};
    static float wrkmem2[16] = {0};

    perspective(projection, 70, 1, 0.001f, 10.0f);
    rotateZ(z_rotation, -M_PI / 4.0f);
    rotateY(y_rotation, -M_PI / 2.0f);
    translate(translation, 0, 0, -4.0f);

    multiply(wrkmem, translation, z_rotation);
    multiply(uniforms.matrix, projection, wrkmem);
    memcpy(uniforms.matrix, z_rotation, 16 * sizeof(float));
}

-(void) render {
    [self updateMatrix];

    id<CAMetalDrawable> drawable = [self.layer nextDrawable];
    id<MTLTexture> framebufferTexture = drawable.texture;

    MTLRenderPassDescriptor *renderPass = [MTLRenderPassDescriptor renderPassDescriptor];
    renderPass.colorAttachments[0].texture = framebufferTexture;
    renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    renderPass.colorAttachments[0].storeAction = MTLStoreActionStore;
    renderPass.colorAttachments[0].loadAction = MTLLoadActionClear;

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];

    id<MTLRenderCommandEncoder> commandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPass];
    [commandEncoder setRenderPipelineState:self.pipeline];
    [commandEncoder setVertexBuffer:self.positionBuffer offset:0 atIndex:0];
    [commandEncoder setVertexBuffer:self.sampleBuffer offset:0 atIndex:1];
    [commandEncoder setVertexBytes:&uniforms length:sizeof(struct Uniforms) atIndex:2];

    [commandEncoder
        drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                   indexCount:self.point_vertices * 3
                    indexType:MTLIndexTypeUInt16
                  indexBuffer:self.indexBuffer
            indexBufferOffset:0
                instanceCount:uniforms.num_frames
    ];

    [commandEncoder endEncoding];

    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

-(void) addToView:(NSView *)view {
    CVDisplayLinkStart(displayLink);
    view.wantsLayer = YES;
    view.layer = self.layer;
    self.currentView = view;

    NSWindow *window = [view window];
    window.title = @"Trololo";

    NSLog(@"%@", window);
}

-(void) removeFromView {
    if (self.currentView != NULL) {
        CVDisplayLinkStop(displayLink);
        self.currentView.layer = NULL;
        self.currentView.wantsLayer = NO;
        self.currentView = NULL;
    }
}
@end

extern void objc_init(zig_log log_fn, char *vst_path, void** renderer_inst) {
    char *log_path = malloc(4096);

    if (sprintf(log_path, "%s/%s", vst_path, "renderer.log") < 0) {
        *renderer_inst = NULL;
        NSLog(@"Failed to build NSLog path");
        log_fn("Failed to build NSLog path");
        return;
    }

    log_fn(log_path);

    freopen(log_path, "a+", stderr);
    free(log_path);

    Renderer *renderer = [Renderer alloc];
    renderer->log_debug = log_fn;
    [renderer setup:vst_path];

    *renderer_inst = (void*) renderer;

    NSLog(@"Setup complete");
}

extern void editor_close(void* renderer_inst, NSView* view) {
    [(Renderer*) renderer_inst removeFromView];
}

extern void editor_open(void* renderer_inst, NSView* view) {
    [(Renderer*) renderer_inst addToView:view];
}

extern void update_buffer(void* renderer_inst, float *ptr, uintptr_t len) {
    [(Renderer*) renderer_inst updateBuffer:ptr len:len];
}

static CVReturn renderCallback(CVDisplayLinkRef displayLink,
        const CVTimeStamp *inNow,
        const CVTimeStamp *inOutputTime,
        CVOptionFlags flagsIn,
        CVOptionFlags *flagsOut,
        void *displayLinkContext
) {
    [(__bridge Renderer *)displayLinkContext render];
    return kCVReturnSuccess;
}
