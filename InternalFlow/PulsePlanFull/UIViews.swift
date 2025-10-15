import SwiftUI

// MARK: - Main Tab
struct MainTabView: View {
    enum Tab { case dashboard, tasks, add }
    @State private var tab: Tab = .dashboard
    var body: some View {
        ZStack(alignment:.bottom){
            Group{
                switch tab{
                case .dashboard: NavigationView{ DashboardScreen() }
                case .tasks: NavigationView{ TasksScreen() }
                case .add: NavigationView{ AddTaskScreen() }
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity)
            CustomTabBar(current:$tab)
        }
    }
}

// MARK: - Custom Tab Bar
private struct CustomTabBar: View {
    @Binding var current: MainTabView.Tab
    func btn(icon:String,label:String,tag:MainTabView.Tab)->some View{
        Button{
            current=tag
        }label:{
            VStack(spacing:2){
                Image(systemName: icon)
                    .renderingMode(.template)
                    .foregroundColor(current==tag ? Color("Primary") : .gray)
                Text(label).font(.system(size:11,weight:.medium))
                    .foregroundColor(current==tag ? Color("Primary"):.gray)
            }.frame(maxWidth:.infinity)
        }
    }
    var body: some View{
        HStack{
            btn(icon:"chart.bar",label:"Dashboard",tag:.dashboard)
            btn(icon:"checklist",label:"Tasks",tag:.tasks)
            btn(icon:"plus",label:"Add",tag:.add)
        }
        .padding(.vertical,8)
        .background(Color.white)
        .overlay(Divider(),alignment:.top)
        .shadow(color:.black.opacity(0.05),radius:2,y:1)
    }
}

// MARK: - Dashboard
struct DashboardScreen: View {
    @EnvironmentObject var hk:HealthKitManager
    @EnvironmentObject var advisor:Advisor
    var body: some View{
        ScrollView{
            VStack(alignment:.leading,spacing:24){
                Header()
                EnergyRing(readiness: hk.readiness)
                StatGrid(hrv:68,resting:64)
                SuggestionCard(text: advisor.latestSuggestion)
                NextUpSection()
            }.padding(.horizontal).padding(.bottom,120)
        }.navigationBarHidden(true)
        .background(Color("AppBackground").ignoresSafeArea())
    }
    private struct Header:View{
        var body: some View{
            VStack(alignment:.leading,spacing:4){
                Text(Date(),format:.dateTime.weekday().day().month())
                    .font(.caption).foregroundColor(.gray)
                Text("Good afternoon, Alex").font(.title3.weight(.semibold))
            }
        }
    }
}

// Energy Ring
private struct EnergyRing: View {
    var readiness:Double
    var body: some View{
        ZStack{
            Circle().stroke(Color("Secondary").opacity(0.2),lineWidth:15)
            Circle()
                .trim(from:0,to:readiness/100)
                .stroke(AngularGradient(colors:[Color("Primary"),Color("Secondary")],center:.center),
                        style:StrokeStyle(lineWidth:15,lineCap:.round))
                .rotationEffect(.degrees(-90))
            VStack{
                Text("\(Int(readiness))%").font(.system(size:28,weight:.bold)).foregroundColor(Color("Primary"))
                Text("Energy Level").font(.caption).foregroundColor(.gray)
            }
        }.frame(width:220,height:220).frame(maxWidth:.infinity)
    }
}

// Stat Grid
private struct StatGrid: View {
    var hrv:Int; var resting:Int
    var body: some View{
        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:16){
            StatCard(title:"HRV",value:"\(hrv) ms",icon:"waveform.path.ecg",tint:.green,note:"+12 %")
            StatCard(title:"Resting HR",value:"\(resting) bpm",icon:"heart",tint:.blue,note:"-3 bpm")
        }
    }
}
private struct StatCard:View{
    var title,value,icon,note:String; var tint:Color
    var body: some View{
        VStack(alignment:.leading,spacing:4){
            HStack{
                Text(title).font(.caption).foregroundColor(.gray)
                Spacer()
                Circle().fill(tint.opacity(0.1)).frame(width:24,height:24)
                    .overlay(Image(systemName:icon).font(.system(size:12)).foregroundColor(tint))
            }
            Text(value).font(.title3.weight(.semibold))
            Text(note).font(.caption2).foregroundColor(.gray)
        }.padding().background(RoundedRectangle(cornerRadius:12).fill(Color.white))
        .shadow(color:.black.opacity(0.03),radius:2,y:1)
    }
}

// Suggestion Card
private struct SuggestionCard:View{
    var text:String
    var body: some View{
        VStack(alignment:.leading,spacing:12){
            HStack(alignment:.top){
                Circle().fill(Color("Primary").opacity(0.1)).frame(width:40,height:40)
                    .overlay(Image(systemName:"scope").foregroundColor(Color("Primary")))
                Text(text).font(.body)
            }
            HStack{
                Button("Start Now"){}.buttonStyle(PrimaryButton())
                Button("Later"){}.buttonStyle(SecondaryButton())
            }
        }.padding().background(RoundedRectangle(cornerRadius:16).fill(Color.white))
    }
}

// Next Up Section
private struct NextUpSection:View{
    @EnvironmentObject var tasks:TaskStore
    var body: some View{
        VStack(alignment:.leading,spacing:12){
            Text("Next Up").font(.title3.weight(.semibold))
            ForEach(tasks.tasks.prefix(2)){ TaskCard(task:$0) }
        }
    }
}
private struct TaskCard:View{
    var task:Task
    var body: some View{
        VStack(alignment:.leading,spacing:8){
            HStack{
                Text(task.title).font(.headline)
                Spacer()
                Capsule().fill(Color.blue.opacity(0.1))
                    .frame(height:20).overlay(Text(task.category.rawValue.capitalized)
                    .font(.caption).foregroundColor(.blue).padding(.horizontal,6))
            }
            EffortDots(effort:task.effort)
        }.padding().background(RoundedRectangle(cornerRadius:12).fill(Color.white))
        .shadow(color:.black.opacity(0.03),radius:1,y:1)
    }
}
private struct EffortDots:View{
    var effort:Int
    var body: some View{
        HStack(spacing:4){
            ForEach(0..<5){ i in Circle().fill(i<effort ? Color("Primary") : Color.gray.opacity(0.3))
                    .frame(width:6,height:6)}
            Text(effortText).font(.caption).foregroundColor(.gray)
        }
    }
    private var effortText:String{
        switch effort{case 1:"Low";case 2...3:"Medium";default:"High"}
    }
}

// MARK: - Tasks Screen
struct TasksScreen:View{
    @EnvironmentObject var tasks:TaskStore
    @State private var filter:TaskCategory? = nil
    @State private var showAdd=false
    var body: some View{
        VStack(spacing:0){
            CategoryScroll(filter:$filter)
            List{
                ForEach(filtered(tasks.tasks)){ TaskRow(task:$0) }
                    .onDelete{ tasks.remove(at: $0) }
            }.listStyle(.plain)
        }.navigationTitle("My Tasks")
        .toolbar{ Button{ showAdd=true }label{ Image(systemName:"plus") } }
        .sheet(isPresented:$showAdd){ AddTaskScreen() }
    }
    private func filtered(_ list:[Task])->[Task]{
        guard let f=filter else{ return list }; return list.filter{ $0.category==f }
    }
}

private struct CategoryScroll:View{
    @Binding var filter:TaskCategory?
    var body: some View{
        ScrollView(.horizontal,showsIndicators:false){
            HStack(spacing:8){
                Chip(label:"All",active:filter==nil){ filter=nil }
                ForEach(TaskCategory.allCases,id:\.self){ cat in
                    Chip(label:cat.rawValue.capitalized,active:filter==cat){ filter=cat }
                }
            }.padding(.horizontal)
        }.padding(.vertical,8)
    }
    private func Chip(label:String,active:Bool,action:@escaping()->Void)->some View{
        Button(action:action){
            Text(label).font(.system(size:13,weight:.medium))
                .padding(.horizontal,16).padding(.vertical,8)
                .background(active ? Color("Primary") : Color.gray.opacity(0.1))
                .foregroundColor(active ? .white : .gray)
                .clipShape(Capsule())
        }
    }
}

private struct TaskRow:View{
    var task:Task
    var body: some View{
        HStack{
            Text(task.title)
            Spacer()
            EffortDots(effort:task.effort)
        }
    }
}

// MARK: - Add Task Screen
struct AddTaskScreen:View{
    @EnvironmentObject var tasks:TaskStore
    @EnvironmentObject var speech:SpeechManager
    @Environment(\.dismiss) var dismiss
    @State private var title="" ; @State private var effort=3.0
    @State private var category:TaskCategory = .work
    @State private var due:Date = .now
    var body: some View{
        ScrollView{
            VStack(alignment:.leading,spacing:24){
                Text("What would you like to accomplish?")
                    .font(.headline)
                TextField("Task title",text:$title).textFieldStyle(.roundedBorder)
                EffortSlider(effort:$effort)
                CategoryPicker(selected:$category)
                DatePicker("Due Date",selection:$due,displayedComponents:.date)
                    .datePickerStyle(.compact)
                HStack(spacing:12){
                    Button("Add Task"){
                        tasks.add(Task(title:title,due:due,category:category,effort:Int(effort)))
                        dismiss()
                    }.buttonStyle(PrimaryButton())
                    Button("Cancel"){ dismiss() }.buttonStyle(SecondaryButton())
                }
            }.padding()
        }.navigationTitle("Add Task")
    }
}

private struct EffortSlider:View{
    @Binding var effort:Double
    var body: some View{
        VStack(alignment:.leading){
            Text("Effort Level").font(.caption)
            Slider(value:$effort,in:1...5,step:1)
        }
    }
}

private struct CategoryPicker:View{
    @Binding var selected:TaskCategory
    var body: some View{
        VStack(alignment:.leading){
            Text("Category").font(.caption)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8){
                ForEach(TaskCategory.allCases,id:\.self){ cat in
                    Button{
                        selected=cat
                    }label{
                        HStack{
                            Image(systemName:"circle.fill")
                            Text(cat.rawValue.capitalized)
                        }
                        .font(.caption)
                        .padding(8)
                        .frame(maxWidth:.infinity)
                        .background(selected==cat ? Color("Primary").opacity(0.15):Color.gray.opacity(0.1))
                        .foregroundColor(selected==cat ? Color("Primary"):.gray)
                        .clipShape(RoundedRectangle(cornerRadius:8))
                    }
                }
            }
        }
    }
}

// MARK: - Buttons
struct PrimaryButton:ButtonStyle{
    func makeBody(configuration:Configuration)->some View{
        configuration.label
            .frame(maxWidth:.infinity).padding()
            .background(Color("Primary")).foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius:8))
            .opacity(configuration.isPressed ? 0.8:1)
    }
}
struct SecondaryButton:ButtonStyle{
    func makeBody(configuration:Configuration)->some View{
        configuration.label.frame(maxWidth:.infinity).padding()
            .background(Color.gray.opacity(0.1)).foregroundColor(.gray)
            .clipShape(RoundedRectangle(cornerRadius:8))
    }
}
