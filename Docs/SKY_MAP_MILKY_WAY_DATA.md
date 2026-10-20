# Sky Map Milky Way data

AstroJournal Sky Map V2 uses a measured visible-light all-sky panorama rather
than the former 2.2 µm COBE/DIRBE brightness grid. The visible-light source
preserves the Milky Way's bright star clouds, dark dust lanes, varying width,
and Galactic bulge structure.

## Source and credit

- Data: Axel Mellinger's visible-light all-sky panorama
- Credit: Axel Mellinger, University of Potsdam
- Distribution source: Stellarium `textures/milkyway.png`
  - <https://github.com/Stellarium/stellarium/blob/master/textures/milkyway.png>
  - <https://raw.githubusercontent.com/Stellarium/stellarium/master/textures/milkyway.png>
- Source SHA-256:
  `95CA887AE2FD6811A202F83BCCB1376819957D074EED92E4DF17F9CBEA83DF97`
- Scientific description: Mellinger, *A Color All-Sky Panorama Image of the
  Milky Way*, PASP 121 (2009)
  - <https://arxiv.org/abs/0908.4360>

The panorama is assembled from broadband visible-light photographs obtained
from dark sites in both hemispheres. It is an observational image, not a
procedurally generated Milky Way.

## Redistribution permission

Stellarium's `CREDITS.md` identifies Axel Mellinger as the author and records
his permission to modify and redistribute the image when proper credit to the
original image is given:

- <https://github.com/Stellarium/stellarium/blob/master/CREDITS.md>

AstroJournal includes a modified, downsampled derivative and retains the above
credit. No Stellarium program code is copied into the application.

## Bundled derivative

`assets/sky_map/mellinger_stellarium_visible_1024.png`:

- original source: 2048 × 1024 RGB PNG, 1,003,398 bytes
- bundled derivative: 1024 × 512 RGBA PNG, 877,082 bytes
- derivative SHA-256:
  `AECCED06EB12DC34257118F8F43B641DB3F5AF11286262ECB92C94D30756AA81`
- resize: Lanczos downsampling
- detail treatment: restrained 1 px unsharp mask
- background treatment: small luminance baseline subtraction followed by an
  asinh contrast curve
- color treatment: source chroma retained; no false-color mapping
- alpha treatment: derived from visible luminance, with transparent dark sky
  and a maximum alpha of 220

The previous 4,474-byte COBE/DIRBE JSON asset was removed. The packaged asset
set therefore grows by 872,608 bytes (about 0.83 MiB) before package-level
compression.

## Texture coordinates and runtime flow

The texture follows the orientation used by Stellarium's Milky Way renderer:

- projection: J2000 equatorial equirectangular
- horizontal texture coordinate: `u = normalize(90° - RA) / 360°`
- vertical texture coordinate: `v = (90° - Dec) / 180°`
- RA 90° is the wrapped left/right seam
- Dec +90° is the top edge

At runtime:

1. Decode the 1024 × 512 image once and cache it.
2. Build a 3° J2000 RA/Dec texture mesh (121 × 61 vertices) once.
3. Convert those vertices to Alt/Az using `CelestialPositionService` and the
   same selected time and observing site as stars and catalog objects.
4. Project the Alt/Az mesh with the existing
   `SkyMapHorizontalProjectionService`.
5. Draw the texture before the Alt/Az grid, constellation lines, stars,
   catalog objects, and equipment FOV overlay.

The duplicated seam vertices map to the same celestial direction, preventing a
0°/360° gap. Date, time, and observing-site changes recompute only the
equatorial-to-horizontal rotation; they do not reload the texture. Daylight,
twilight, below-horizon fading, and the existing Milky Way switch remain
runtime painter policies.

## Improvement over the former infrared layer

The retired COBE/DIRBE asset was a 120 × 21 scalar grid covering only Galactic
latitudes -30° to +30°. Its near-infrared intensity was useful for locating the
Galactic plane but appeared as a broad gray glow and could not reproduce the
visible dark rifts. The new texture uses visible color and 1024 × 512 alpha
detail, while the 3° geometry mesh limits projection cost on Android and
Windows.
