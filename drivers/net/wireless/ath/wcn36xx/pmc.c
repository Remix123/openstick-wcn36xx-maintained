/*
 * Copyright (c) 2013 Eugene Krasnikov <k.eugene.e@gmail.com>
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
 * SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION
 * OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
 * CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include "wcn36xx.h"

int wcn36xx_pmc_enter_bmps_state(struct wcn36xx *wcn,
				 struct ieee80211_vif *vif)
{
	int ret = 0;
	struct wcn36xx_vif *vif_priv = wcn36xx_vif_to_priv(vif);

	if (!vif_priv->allow_bmps ||
	    (wcn36xx_bmps_guard && vif_priv->bmps_failed))
		return -EAGAIN;

	/* The downstream firmware requires a fully-established BSS context.
	 * Do not send ENTER_BMPS while association/configuration is still in
	 * flight or before the first beacon supplied valid timing information. */
	if (wcn36xx_bmps_guard &&
	    (!vif_priv->sta_assoc || vif_priv->is_joining ||
	     vif_priv->bss_index == WCN36XX_HAL_BSS_INVALID_IDX ||
	     !vif->bss_conf.assoc || !vif->bss_conf.beacon_int ||
	     !vif->bss_conf.dtim_period || !vif->bss_conf.sync_tsf))
		return -ENOTSUPP;

	ret = wcn36xx_smd_enter_bmps(wcn, vif);
	if (!ret) {
		wcn36xx_dbg(WCN36XX_DBG_PMC, "Entered BMPS\n");
		vif_priv->pw_state = WCN36XX_BMPS;
		vif->driver_flags |= IEEE80211_VIF_BEACON_FILTER;
	} else {
		/* A rejected request is persistent for this firmware/BSS state.
		 * Stop retrying it and leave the interface in full power.  The
		 * next association resets bmps_failed and gets a fresh attempt. */
		if (wcn36xx_bmps_guard) {
			vif_priv->bmps_failed = true;
			wcn36xx_warn("BMPS rejected (err=%d); keeping full power until reassociation\n",
				     ret);
		}
	}
	return ret;
}

int wcn36xx_pmc_exit_bmps_state(struct wcn36xx *wcn,
				struct ieee80211_vif *vif)
{
	struct wcn36xx_vif *vif_priv = wcn36xx_vif_to_priv(vif);

	if (WCN36XX_BMPS != vif_priv->pw_state) {
		/* Unbalanced call or last BMPS enter failed */
		wcn36xx_dbg(WCN36XX_DBG_PMC,
			    "Not in BMPS mode, no need to exit\n");
		return -EALREADY;
	}
	wcn36xx_smd_exit_bmps(wcn, vif);
	vif_priv->pw_state = WCN36XX_FULL_POWER;
	vif->driver_flags &= ~IEEE80211_VIF_BEACON_FILTER;
	return 0;
}

int wcn36xx_enable_keep_alive_null_packet(struct wcn36xx *wcn,
					  struct ieee80211_vif *vif)
{
	wcn36xx_dbg(WCN36XX_DBG_PMC, "%s\n", __func__);
	return wcn36xx_smd_keep_alive_req(wcn, vif,
					  WCN36XX_HAL_KEEP_ALIVE_NULL_PKT);
}
