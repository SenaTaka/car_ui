//
//  ChannelHelp.swift
//  car_ui
//
//  各チャンネル(OBD PID / GPS / 加速度計)の平易な説明文。
//  データタブの行をタップしたときの解説シートで表示する。
//

import Foundation

enum ChannelHelp {
    /// チャンネル ID に対応する説明文。未定義のチャンネルは nil。
    static func text(for channelID: String) -> String? {
        byChannel[channelID]
    }

    private static let byChannel: [String: String] = {
        var d: [String: String] = [
            "obd.04": String(localized: "エンジンが出せる最大出力に対する現在の負荷の割合です。登坂や加速で高くなります。"),
            "obd.05": String(localized: "エンジン冷却水の温度です。通常走行では約 80〜100℃ で安定します。低いうちは暖機中です。"),
            "obd.0A": String(localized: "燃料ポンプが作る燃料ラインの圧力です。"),
            "obd.0B": String(localized: "吸気マニホールド内の絶対圧です。アイドリングで低く、アクセルを踏むと大気圧(約 100 kPa)に近づきます。ターボ車は過給時にそれを上回ります。"),
            "obd.0C": String(localized: "エンジン(クランクシャフト)の毎分回転数です。"),
            "obd.0D": String(localized: "ECU が認識している車速です。スピードメーターの表示とは数 km/h ずれることがあります。"),
            "obd.0E": String(localized: "点火プラグが火花を飛ばすタイミング(上死点前の進角)です。負荷や回転数に応じて ECU が調整します。"),
            "obd.0F": String(localized: "エンジンに吸い込まれる空気の温度です。高いと出力がやや低下します。"),
            "obd.10": String(localized: "エンジンが 1 秒間に吸い込む空気の質量です。負荷とともに増えます。"),
            "obd.11": String(localized: "スロットルバルブの開き具合です。"),
            "obd.1F": String(localized: "エンジンを始動してからの経過時間です。"),
            "obd.21": String(localized: "チェックエンジンランプ(MIL)が点灯してから走行した距離です。"),
            "obd.22": String(localized: "吸気マニホールド圧を基準にした燃料圧力です。"),
            "obd.23": String(localized: "直噴エンジンの高圧燃料レールの圧力です。"),
            "obd.2C": String(localized: "排気再循環(EGR)バルブへの開度指令です。NOx 低減のため排気の一部を吸気へ戻します。"),
            "obd.2D": String(localized: "EGR の指令値と実際の開度との差です。"),
            "obd.2E": String(localized: "燃料タンクの蒸発ガスをキャニスターからエンジンへ吸わせる制御(パージ)の開度です。"),
            "obd.2F": String(localized: "燃料タンク残量の割合です。"),
            "obd.31": String(localized: "故障コード(DTC)を消去してから走行した距離です。"),
            "obd.33": String(localized: "現在地の大気圧です。海面で約 100 kPa、高地では低くなります。"),
            "obd.42": String(localized: "ECU に供給されている電圧です。エンジン稼働中は約 13.5〜14.5 V が正常の目安です。"),
            "obd.43": String(localized: "吸入空気量をもとに計算した負荷率です。"),
            "obd.44": String(localized: "ECU が目標とする空燃比(λ)です。1.0 が理論空燃比を表します。"),
            "obd.45": String(localized: "アイドル位置を 0% とした相対的なスロットル開度です。"),
            "obd.46": String(localized: "車両が測定した外気温度です。"),
            "obd.47": String(localized: "2 系統目のスロットルセンサーの開度です(冗長系)。"),
            "obd.4C": String(localized: "ECU がスロットルに指示している目標開度です。"),
            "obd.52": String(localized: "燃料に含まれるエタノールの混合率です(フレックス燃料車向け)。"),
            "obd.5A": String(localized: "学習した 0 点を基準にしたアクセルの踏み込み量です。"),
            "obd.5C": String(localized: "エンジンオイルの温度です。水温より暖まるのが遅く、スポーツ走行では高温に注意してください。"),
            "obd.5E": String(localized: "現在の燃料消費量(1 時間あたりのリットル)です。"),
            "obd.61": String(localized: "ドライバーの操作から算出された要求トルクです(基準トルクに対する割合)。"),
            "obd.62": String(localized: "現在エンジンが実際に出しているトルクです(基準トルクに対する割合)。"),
            "obd.63": String(localized: "トルクの % 値の基準となるエンジン固有の基準トルクです。"),
            "meta.voltage": String(localized: "OBD アダプタが測定した車両バッテリーの電圧です。エンジン停止時は約 12.5 V、走行中(充電中)は約 14 V が目安です。"),
            "gps.lat": String(localized: "GPS による現在の緯度です。"),
            "gps.lon": String(localized: "GPS による現在の経度です。"),
            "gps.speed": String(localized: "GPS の位置変化から算出した車速です。トンネルなど電波の届かない場所では途切れます。"),
            "gps.altitude": String(localized: "GPS による標高です。"),
            "gps.course": String(localized: "進行方向の方位です(0° = 北、時計回り)。"),
            "gps.distance": String(localized: "このセッションで GPS が積算した走行距離です。"),
            "motion.gx": String(localized: "旋回時に横方向へかかる加速度です。端末の取り付け角度によらず水平面で算出します。"),
            "motion.gy": String(localized: "加速・減速で前後方向にかかる加速度です。"),
            "motion.gmag": String(localized: "横 G と前後 G を合成した加速度の大きさです。"),
        ]

        // 燃料補正(短期/長期 × バンク 1/2)
        let shortTrim = String(localized: "O2 センサーの値をもとに ECU が瞬間的に行う燃料量の補正です。±10% 以内が正常の目安です。")
        let longTrim = String(localized: "学習により長期的に適用される燃料量の補正です。大きくプラスに振れる場合は吸気漏れや燃圧低下などの兆候の可能性があります。")
        d["obd.06"] = shortTrim
        d["obd.08"] = shortTrim
        d["obd.07"] = longTrim
        d["obd.09"] = longTrim

        // O2 センサー(B=バンク、S=位置)
        let o2 = String(localized: "排気中の酸素濃度を電圧で示します。触媒前(S1)は 0.1〜0.9 V を往復し、触媒後(S2)が安定していれば触媒は正常に働いています。B はバンク(気筒列)です。")
        for suffix in ["14", "15", "16", "17", "18", "19", "1A", "1B"] {
            d["obd.\(suffix)"] = o2
        }

        // 触媒温度
        let catalyst = String(localized: "排気ガスを浄化する触媒の温度です。走行中は数百 ℃ まで上がります。")
        for suffix in ["3C", "3D", "3E", "3F"] {
            d["obd.\(suffix)"] = catalyst
        }

        // アクセルペダル(冗長センサー)
        let pedal = String(localized: "アクセルペダルの踏み込み量です。安全のため複数系統(D/E)で二重に検出しています。")
        d["obd.49"] = pedal
        d["obd.4A"] = pedal

        return d
    }()
}
