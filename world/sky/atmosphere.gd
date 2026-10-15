class_name Atmosphere
extends RefCounted
## CPU twin of the single-scattering atmosphere in world_sky.gdshader
## (Rayleigh + Mie + ozone over a spherical planet, Chapman-function optical
## depths). SkyController evaluates it a few times per second so the sun's
## colour, the ambient light, the fog and the clouds' lighting all agree with
## what the sky shader draws. Distances in km. Keep the constants in sync with
## the shader.

const EARTH_R := 6360.0
const ATMOS_R := 6420.0
const H_R := 8.0
const H_M := 1.2
const BETA_R := Vector3(5.8e-3, 13.5e-3, 33.1e-3)
const BETA_M := 14e-3
const MIE_EXT := 1.11
## Ozone absorption, folded into the Rayleigh density profile.
const BETA_O := Vector3(0.65e-3, 1.881e-3, 0.085e-3) * 1.9
const CAM_H := 0.25
## Sun irradiance scale: sky radiance in scene units for a white sun of energy 1.
const SUN_E := 20.0


## Transmittance of sunlight from space down to the viewer, per colour channel.
static func sun_transmittance(sun_dir: Vector3, height_km := CAM_H) -> Vector3:
	var r := EARTH_R + height_km
	var mu := sun_dir.y
	if _hits_planet(r, mu):
		# Below the horizon: soft fade so the light does not snap off.
		var below := clampf(1.0 + (mu + _horizon_mu(r)) * 40.0, 0.0, 1.0)
		if below <= 0.0:
			return Vector3.ZERO
		mu = -_horizon_mu(r) + 0.0001
		var od := _optical_depth(r, mu)
		return _exp3(-od) * below
	return _exp3(-_optical_depth(r, mu))


## Sky radiance seen from the ground in direction `dir` (single scattering, coarse).
static func sky_radiance(dir: Vector3, sun_dir: Vector3, samples := 8) -> Vector3:
	var d := dir.normalized()
	d.y = maxf(d.y, 0.0)
	d = d.normalized()
	var r0 := EARTH_R + CAM_H
	var tmax := _ray_sphere(r0, d.y, ATMOS_R)
	var mu_s := d.dot(sun_dir)
	var pr := 3.0 / (16.0 * PI) * (1.0 + mu_s * mu_s)
	var g := 0.76
	var pm := 3.0 / (8.0 * PI) * ((1.0 - g * g) * (1.0 + mu_s * mu_s)) / ((2.0 + g * g) * pow(1.0 + g * g - 2.0 * g * mu_s, 1.5))
	var sum_r := Vector3.ZERO
	var sum_m := Vector3.ZERO
	var od_r := 0.0
	var od_m := 0.0
	for i in samples:
		var f := (float(i) + 0.5) / float(samples)
		var t := tmax * f * f
		var ds := tmax * (float(i + 1) * float(i + 1) - float(i) * float(i)) / float(samples * samples)
		var px := d * t
		var r := sqrt(px.x * px.x + px.z * px.z + (r0 + px.y) * (r0 + px.y))
		var h := r - EARTH_R
		var dr := exp(-h / H_R) * ds
		var dm := exp(-h / H_M) * ds
		od_r += dr
		od_m += dm
		var up := Vector3(px.x, r0 + px.y, px.z) / r
		var smu := up.dot(sun_dir)
		if _hits_planet(r, smu):
			continue
		var sun_od := _optical_depth(r, smu)
		var view_od := (BETA_R + BETA_O) * od_r + Vector3.ONE * (BETA_M * MIE_EXT * od_m)
		var tr := _exp3(-(sun_od + view_od))
		sum_r += tr * dr
		sum_m += tr * dm
	return (sum_r * BETA_R * pr + sum_m * BETA_M * pm) * SUN_E


static func _optical_depth(r: float, mu: float) -> Vector3:
	var odr := _chapman(r, mu, H_R) * H_R
	var odm := _chapman(r, mu, H_M) * H_M
	return (BETA_R + BETA_O) * odr + Vector3.ONE * (BETA_M * MIE_EXT * odm)


## Schueler's Chapman approximation: relative air mass times exp(-h/H).
static func _chapman(r: float, mu: float, scale_h: float) -> float:
	var x := r / scale_h
	var h := (r - EARTH_R) / scale_h
	var xe := EARTH_R / scale_h
	var c := sqrt(x)
	if mu >= 0.0:
		return c / (c * mu + 1.0) * exp(-h)
	var x0 := sqrt(1.0 - mu * mu) * x
	var c0 := sqrt(x0)
	return 2.0 * c0 * exp(xe - x0) - c / (1.0 - c * mu) * exp(-h)


static func _hits_planet(r: float, mu: float) -> bool:
	return mu < -_horizon_mu(r)


static func _horizon_mu(r: float) -> float:
	return sqrt(maxf(1.0 - (EARTH_R / r) * (EARTH_R / r), 0.0))


static func _ray_sphere(r: float, mu: float, radius: float) -> float:
	var b := r * mu
	var c := r * r - radius * radius
	return -b + sqrt(maxf(b * b - c, 0.0))


static func _exp3(v: Vector3) -> Vector3:
	return Vector3(exp(v.x), exp(v.y), exp(v.z))
