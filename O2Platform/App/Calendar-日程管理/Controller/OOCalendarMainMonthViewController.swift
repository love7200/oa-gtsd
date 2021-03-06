//
//  OOCalendarMainMonthViewController.swift
//  O2Platform
//
//  Created by FancyLou on 2018/7/30.
//  Copyright © 2018 zoneland. All rights reserved.
//

import UIKit
import FSCalendar
import CocoaLumberjack
import Promises




class OOCalendarMainMonthViewController: UIViewController {

    //MARK: - arguments
    var eventsByDate:[String:[OOCalendarEventInfo]]?{
        didSet {
            //todo
        }
    }
    var calendarIds:[String] = []
    private var eventShowList:[OOCalendarEventInfo] = []
    private var _today: Date?
    private var _selectDay: Date?
    private var _currentPerson: String?
    private var _startTime: Date?
    private var _endTime: Date?
    private lazy var viewModel: OOCalendarViewModel = {
        return OOCalendarViewModel()
    }()
    
    //MARK: - IB
    fileprivate var calendarViewDic: [Int : FSCalendar] = [:]
  
    // 这个按钮是日历
    @IBAction func todayAction(_ sender: Any) {
        _selectDay = _today
        calendarViewDic[0]?.select(_today)
        
    }
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var calendarBtn: UIButton!
    @IBOutlet weak var todayBtn: UIButton!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "关闭", style: .plain, target: self, action: #selector(closeWindow))
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: #imageLiteral(resourceName: "add"), style: .plain, target: self, action: #selector(addEvent))
        // Do any additional setup after loading the view.
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.tableFooterView = UIView(frame: CGRect.zero)
        self.calendarBtn.theme_setTitleColor(ThemeColorPicker(keyPath: "Base.base_color"), forState: .normal)
        self.todayBtn.theme_setTitleColor(ThemeColorPicker(keyPath: "Base.base_color"), forState: .normal)
        
        
        //初始化
        let account = O2AuthSDK.shared.myInfo()
        _currentPerson = account?.distinguishedName
        _today = Date()
        _selectDay = _today
        _startTime = DateUtil.share.monthStartDate(date: _today!)
        _endTime = DateUtil.share.monthEndDate(startDate: _startTime!)
        setNavTitle(date: _today!)
        NotificationCenter.default.addObserver(self, selector: #selector(setTheCalendarIds(_:)), name: OONotification.calendarIds.notificationName, object: nil)
    }
    override func viewWillAppear(_ animated: Bool) {
        loadData()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    //设置
    @objc private func setTheCalendarIds(_ notification:NSNotification) {
        DDLogDebug("接收到通知消息")
        if let ids = notification.object as? [String] {
            DDLogDebug("设置ids：\(ids)")
            self.calendarIds = ids
        }
    }
    /*
    // MARK: - Navigation
    // In a storyboard-based application, you will often want to do a little preparation before navigation
     */
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showEventDetail" {
            let add = sender as? String
            if add != nil && add == "add" {
                DDLogInfo("新增日程！")
            }else {
                let row  = tableView.indexPathForSelectedRow!.row
                let destination = segue.destination as! OOCalendarEventViewController
                destination.eventInfo = self.eventShowList[row]
            }
        }
        if segue.identifier == "showCalendarList" {
            if !self.calendarIds.isEmpty {
                if let dest = segue.destination as? OOCalendarLeftMenuController {
                    dest.calendarIds = self.calendarIds
                }
            }
        }
    }
 
    //MARK: - private func
    
    @objc func closeWindow() {
        self.navigationController?.dismiss(animated: true, completion: nil)
    }
    
    @objc func addEvent() {
        self.performSegue(withIdentifier: "showEventDetail", sender: "add")
    }
    private func loadData() {
        self.showLoading()
        let filter = OOCalendarEventFilter()
        filter.startTime = self._startTime?.toString("yyyy-MM-dd HH:mm:ss")
        filter.endTime = self._endTime?.toString("yyyy-MM-dd HH:mm:ss")
        filter.calendarIds = self.calendarIds
        
        viewModel.filterCalendarEventList(filter: filter).then { (response) -> Promise<[String:[OOCalendarEventInfo]]>  in
            return Promise<[String:[OOCalendarEventInfo]]> { fulfill, reject in
                var result: [String:[OOCalendarEventInfo]] = [:]
                if let one = response.inOneDayEvents {
                    one.forEach({ (event) in
                        if let date = event.eventDate {
                            if var array = result[date] {
                                event.inOneDayEvents?.forEach({ (info) in
                                    array.append(info)
                                })
                                result[date] = array
                            }else {
                                result[date] = event.inOneDayEvents ?? []
                            }
                        }
                    })
                }
                if let all = response.wholeDayEvents {
                    DDLogInfo("全天事件。。。。\(all.count)")
                    all.forEach({ (event) in
                        //处理连续多天的事件。。。。。
                        let dateArray = self.splitDays(startDay: event.startTimeStr!, endDay: event.endTimeStr!)
                        for date in dateArray {
                            if var array = result[date] {
                                array.append(event)
                                result[date] = array
                            }else {
                                result[date] = [event]
                            }
                        }
                    })
                }
                fulfill(result)
            }
            }.then { (dict) in
                DDLogInfo("filter 结果： \(dict.count)")
                self.eventsByDate = dict
                // 刷新页面
                self.calendarViewDic[0]?.reloadData()
                self.calendarViewDic[0]?.select(self._selectDay)
                self.selectCalendarDate(self._selectDay!)
        }.always {
            self.hideLoading()
        }.catch { (error) in
                DDLogError(error.localizedDescription)
        }
    }
    
    /**
     * 分割成多天
     * @param startDay yyyy-MM-dd HH:mm:ss
     * @param endDay yyyy-MM-dd HH:mm:ss
     * @return [yyyy-MM-dd]
     */
    private func splitDays(startDay: String, endDay: String) -> [String] {
        var ret:[String] = []
        guard let sDay = Date.date(startDay) else {
            return ret
        }
        guard let eDay = Date.date(endDay) else {
            return ret
        }
        if sDay.haveSameYearMonthAndDay(eDay) {
            ret.append(sDay.toString("yyyy-MM-dd"))
        }else {
            let gap = sDay.betweenDays(eDay)
            for index in 0...gap {
                let nDay = sDay.add(component: .day, value: index)
                ret.append(nDay.toString("yyyy-MM-dd"))
            }
        }
        
        return ret
    }
    
    private func haveEventForDay(_ date:Date) -> Bool{
        guard let dict = eventsByDate else {
            return false
        }
        let key =  self.dateFormatter().string(from: date)
        if dict[key] != nil && (dict[key]?.count)! > 0 {
            return true
        }
        return false
    }
    
    private func dateFormatter() -> DateFormatter {
        var dateFormatter: DateFormatter?
        if dateFormatter == nil {
            dateFormatter = DateFormatter()
            dateFormatter?.dateFormat = "yyyy-MM-dd"
        }
        return dateFormatter!
    }
    
    private func setNavTitle(date: Date) {
        navigationItem.title = date.toString("yyyy年MM月")
    }

    // 选中日历上的日期 刷新日程列表
    private func selectCalendarDate(_ date: Date) {
        let clickDate = date.toString("yyyy-MM-dd")
        DDLogInfo("did select date \(clickDate) ")
        if let showList = eventsByDate?[clickDate] {
            eventShowList = showList
        }else {
            eventShowList.removeAll()
        }
        self.tableView.reloadData()
    }
}

//MARK: - extension
extension OOCalendarMainMonthViewController: UITableViewDelegate, UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        let count = eventShowList.count
        DDLogInfo("row size \(count)")
        return count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CalendarEventCell") as! CalendarEventTableViewCell
        // Configure the cell...
        cell.renderCell(withItem: eventShowList[indexPath.row])
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return CGFloat(300)
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if let view = self.calendarViewDic[section] {
            return view
        }
        let calendar = FSCalendar(frame: CGRect(x: 0, y: 0, width: SCREEN_WIDTH, height: 300))
        calendar.dataSource = self
        calendar.delegate = self
        calendar.firstWeekday = 1
        calendar.appearance.headerTitleColor = UIColor.darkGray//头部字体样色
        calendar.appearance.headerDateFormat = "yyyy年MM月" //头部样式
        calendar.appearance.weekdayTextColor = O2ThemeManager.color(for: "Base.base_color")! // 星期字体颜色
        calendar.locale = Locale.init(identifier: "zh_CN")
        calendar.headerHeight = CGFloat(0)
        calendarViewDic[section] = calendar
        return calendar
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = indexPath.row
        DDLogInfo("click table row:\(row)")
        let event = self.eventShowList[row]
        DDLogInfo("点击了事件：\(event.title ?? "")")
        
        tableView.deselectRow(at: indexPath, animated: false)
        
    }
}


extension OOCalendarMainMonthViewController: FSCalendarDataSource, FSCalendarDelegate {
    func calendar(_ calendar: FSCalendar, boundingRectWillChange bounds: CGRect, animated: Bool) {
        calendar.frame = CGRect(origin: calendar.frame.origin, size: bounds.size)
    }
    
    func calendar(_ calendar: FSCalendar, numberOfEventsFor date: Date) -> Int {
        if haveEventForDay(date) {
            return 1
        }
        return 0
    }
    
    func calendar(_ calendar: FSCalendar, didSelect date: Date, at monthPosition: FSCalendarMonthPosition) {
        _selectDay = date
       selectCalendarDate(date)
    }
   
    
    func calendarCurrentPageDidChange(_ calendar: FSCalendar) {
        let monthStartDay = calendar.currentPage
        let monthEndDay = DateUtil.share.monthEndDate(startDate: monthStartDay)
        self._startTime = monthStartDay
        self._endTime = monthEndDay
        _selectDay = monthStartDay
        setNavTitle(date: monthStartDay)
        loadData()
    }
    
}
