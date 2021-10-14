# Watercolor Shader

A godot shader that makes meshes look like they were painted with watercolors.

![watercolor-shader](https://user-images.githubusercontent.com/2934890/137247782-04a7dbc2-b41f-4bf6-b483-b15ce4f9945b.png)

## Usage

There's three ways to use this shader:

1. For imported meshes with textures, set the mesh's import script to `watercolor/watercolor_import.gd`.
2. For imported meshes with vertex colors, set the mesh's import script to `watercolor/watercolor_import_vert_colors.gd`.
3. Assign the `watercolor_resource.tres` to the target mesh manually.

## How it works

This shader works in two passes. First, it generates a flat color image using the `watercolor_base_pass.shader` script. Then, it does the bulk of it's work in the `watercolor_main_pass.shader` script.

In the main pass, I implement a fragment shader and a light shader. The fragment shader adds a blotchy, paper effect to the whole material. It tries to emulate watercolor by darkening in the center of large area of color (as though multiple brush strokes had overlapped) and lightening around the edges of color islands (as though the brush hadn't quite reached the edge of the island). The darkening and lightening corresponds to the blotchy effect, to make it appear as though the blotches corotate to brush strokes.

In the light shader, I add wavy rings where the light touches the paper, again, corresponding to the blotchy brush strokes below. The rings have a sharp color falloff that's meant to look like color bleeding or a "coffee stain" effect.

## Running the project

When you run the project, you will see the shader applied to two meshes - a house exterior and interior. Use the buttons to switch between meshes.

Also in this project is a directory called `edge_detection_prototype`. Just open `edge_detection.tscn` in the editor and pan around. You'll see dark shading on the edges of the texture. This edge detection is done in the fragment shader using some costly but effective raycasts.
