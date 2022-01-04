//
//  IMAudioView.swift
//  O2Platform
//
//  Created by FancyLou on 2020/6/17.
//  Copyright © 2020 zoneland. All rights reserved.
//

import UIKit

class IMAudioView: UIView {
    
    static let IMAudioView_width: CGFloat = 92
    static let IMAudioView_height: CGFloat = 28
    
    @IBOutlet weak var playImageView: UIImageView!
    @IBOutlet weak var durationLabel: UILabel!
    
    
    override func awakeFromNib() { }
    
    
    func setDuration(duration: String) {
        self.durationLabel.text = "\(duration)\""
        
    }
    /// 设置gif图片 进行播放
    func playAudioGif() {
        let url: URL? = Bundle.main.url(forResource: "chat_play_left", withExtension: "gif")
        guard let u = url else {
            return
        }
        guard let data = try? Data.init(contentsOf: u) else {
            return
        }
        playImageView.image = UIImage.sd_animatedGIF(with: data)
    }
    
    /// 设置静态图片 
    func stopPlayAudioGif() {
        playImageView.image = UIImage(named: "chat_play_left_s")
    }
}
