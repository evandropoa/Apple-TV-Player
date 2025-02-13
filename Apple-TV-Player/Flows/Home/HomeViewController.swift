//
//  HomeViewController.swift
//  Apple-TV-Player
//
//  Created by Mikhail Demidov on 21.10.2020.
//

import UIKit
import Reusable
import os
import Channels

final class HomeViewController: UIViewController {

    @IBOutlet private var tableView: UITableView!

    private var playlistCache: [String:PlaylistItem] = [:]
    
    private lazy var dataSource = DataSource(tableView: self.tableView) { tableView, indexPath, row in
        switch row {
        case .playlist(let name):
            let cell = tableView.dequeueReusableCell(
                for: indexPath, cellType: PlaylistCellView.self)
            cell.textLabel?.text = name
            return cell
        case .providers(let provider):
            let cell = tableView.dequeueReusableCell(
                for: indexPath, cellType: SelectProviderCellView.self)
            cell.textLabel?.text = provider.name
            cell.imageView?.image = provider.icon.map(UIImage.init(cgImage:))
            return cell
        case .addPlaylist:
            let cell = tableView.dequeueReusableCell(
                for: indexPath, cellType: AddPlaylistCellView.self)
            cell.textLabel?.text = NSLocalizedString("Add playlist", comment: "")
            cell.imageView?.image = UIImage(systemName: "square.and.pencil")
            return cell
        case .settings:
            let cell = tableView.dequeueReusableCell(
                for: indexPath, cellType: SettingsCellView.self)
            cell.textLabel?.text = NSLocalizedString("Settings", comment: "")
            cell.imageView?.image = UIImage(systemName: "gear")
            return cell
        }
    }
    private let fsManager = FileSystemManager()
    private var providers: [IpTvProvider] = []
    private let storage = LocalStorage()
    private var handlingCellLongTap = false
    private var highlightingStarted = CFAbsoluteTimeGetCurrent()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.dataSource = dataSource
        tableView.delegate = self
        tableView.register(cellType: SettingsCellView.self)
        tableView.register(cellType: AddPlaylistCellView.self)
        tableView.register(cellType: PlaylistCellView.self)
        tableView.register(cellType: SelectProviderCellView.self)

        reloadUI()
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesEnded(presses, with: event)

        for press in presses {
            if press.type == .playPause {
                if let cell = press.responder as? PlaylistCellView {
                    if let indexPath = tableView.indexPath(for: cell) {
                        handlingCellLongTap = true
                        tableView(tableView, didSelectRowAt: indexPath)
                    }
                }
                return
            }
        }
    }
}

private extension HomeViewController {
    func reloadUI() {
        DispatchQueue.main.async { [unowned self] in
            var snapshot = dataSource.snapshot()
            snapshot.deleteAllItems()
            dataSource.apply(snapshot, animatingDifferences: true)
        }
        DispatchQueue.global(qos: .userInitiated).async { [unowned self] in
            // Skip any local caches to reduce complexity,
            // always reload from the file system.
            var items: [Section: [Row]] = [
                .addPlaylist: [.addPlaylist],
                .settings: [.settings],
                .playlists: [],
                .providers: []
            ]
            do {
                self.providers = try IpTvProviderKind.builtInProviders().map(IpTvProviders.kind(of:))
                items[.providers] = self.providers.map({ Row.providers($0.kind) })
            } catch {
                os_log(.error, "\(error as NSError)")
                self.present(error: error)
            }
            do {
                items[.playlists] = try fsManager.filesNames().map(Row.playlist)
            } catch {
                os_log(.error, "\(error as NSError)")
                self.present(error: error)
            }
    
            DispatchQueue.main.async { [unowned self] in
                var snapshot = dataSource.snapshot()
                snapshot.appendSections(Section.allCases)
                snapshot.appendItems(items[.playlists] ?? [], toSection: .playlists)
                snapshot.appendItems(items[.providers] ?? [], toSection: .providers)
                snapshot.appendItems(items[.addPlaylist] ?? [], toSection: .addPlaylist)
                snapshot.appendItems(items[.settings] ?? [], toSection: .settings)
                dataSource.apply(snapshot, animatingDifferences: true)
    
                self.navigateToLatestProvider()
            }
        }
    }
}

private extension HomeViewController {
    func present(error: Error) {
        RunLoop.main.perform { [unowned self, error] in
            let alert = FailureViewController.make(error: error)
            alert.addOkAction(title: NSLocalizedString("Ok", comment: ""), completion: nil)
            present(alert, animated: true)
        }
    }
    
    func setTableViewProgressView(enabled: Bool) {
        if enabled {
            var snapshot = dataSource.snapshot()
            snapshot.deleteAllItems()
            dataSource.apply(snapshot, animatingDifferences: false)
            tableView.backgroundView = progressBackgroundView()
        } else {
            tableView.backgroundView = nil
            reloadUI()
        }
    }
    
    func progressBackgroundView() -> UIView {
        let view = UIView()
        let progress = UIActivityIndicatorView(style: .large)
        view.addSubview(progress)
        progress.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progress.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            progress.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        progress.startAnimating()
        return view
    }
    
    @discardableResult
    func navigateToLatestProvider() -> Bool {
        if let provider = self.storage.getValue(.current, domain: .common),
           let item = IpTvProviderKind.builtInProviders().first(where: { $0.id == provider }) {
            let row = Row.providers(item)
            let snapshot = dataSource.snapshot()
            if let section = snapshot.indexOfSection(.providers),
               let row = snapshot.indexOfItem(row) {
                let path = IndexPath(row: row, section: section)
                navigate(to: path)
            }
        }
        return false
    }
}

private extension HomeViewController {
    enum Section: Hashable, CaseIterable {
        case playlists
        case providers
        case addPlaylist
        case settings
    }
    
    enum Row: Hashable {
        case playlist(String) // name serves as unique id also.
        case providers(IpTvProviderKind)
        case addPlaylist
        case settings
    }
    
    final class DataSource: UITableViewDiffableDataSource<Section, Row> {
    }
}

extension HomeViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let item = self.dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .playlist(let name) where handlingCellLongTap:
            let actionVC = ActionPlaylistViewController()
            actionVC.deleteAction = { [unowned self] in
                DispatchQueue.global(qos: .userInteractive).async {
                    do {
                        guard let url = try self.fsManager.file(named: name) else { return }
                        try self.fsManager.remove(file: url)
                        self.playlistCache.removeValue(forKey: name)
                        if let url = try self.fsManager.url(named: name) {
                            try self.fsManager.remove(url: url)
                        }
                        DispatchQueue.main.async {
                            self.reloadUI()
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.present(error: error)
                        }
                    }
                }
            }
            if let url = try? self.fsManager.url(named: name) {
                actionVC.updateAction = { [unowned self] in
                    DispatchQueue.main.async {
                        self.setTableViewProgressView(enabled: true)
                    }
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try self.fsManager.download(file: url, name: name)
                            self.playlistCache.removeValue(forKey: name)
                            DispatchQueue.main.async {
                                self.setTableViewProgressView(enabled: false)
                            }
                        } catch {
                            DispatchQueue.main.async {
                                self.present(error: error)
                                self.setTableViewProgressView(enabled: false)
                            }
                        }
                    }
                }
            }
            self.present(actionVC, animated: true)
            handlingCellLongTap = false
            return
        default:
            break
        }
        navigate(to: indexPath)
    }
    
    func tableView(_ tableView: UITableView, didHighlightRowAt indexPath: IndexPath) {
        highlightingStarted = CFAbsoluteTimeGetCurrent()
    }
    
    func tableView(_ tableView: UITableView, didUnhighlightRowAt indexPath: IndexPath) {
        handlingCellLongTap = CFAbsoluteTimeGetCurrent() - highlightingStarted > 1.0
    }
    
    private func navigate(to indexPath: IndexPath) {
        guard let item = dataSource.itemIdentifier(for: indexPath) else {
            return
        }
        switch item {
        case .playlist(let name):
            func present(playlist: PlaylistItem) {
                let playlistVC = PlaylistViewController.instantiate()
                playlistVC.playlist = playlist
                self.present(playlistVC, animated: true) {
                    self.setTableViewProgressView(enabled: false)
                }
            }
            if let playlist = self.playlistCache[name] {
                present(playlist: playlist)
                return
            }
            DispatchQueue.global().async {
                guard let url = try? self.fsManager.file(named: name),
                      let data = self.fsManager.content(of: url) else {
                    return
                }
                DispatchQueue.main.async {
                    self.setTableViewProgressView(enabled: true)
                }
                
                do {
                    // TODO: add ability for top tag `#EXTM3U` read image by name (from channel bundle) | from URL.
                    let tvProvider = try IpTvProviders.kind(of: .dynamic(m3u: data, name: name))
                    let playlist = PlaylistItem(channels: tvProvider.bundles.flatMap({ $0.playlist.channels }))

                    let myPrivatePlaylistToNotCacheBecauseStreamURLLifetimeShort = [
                        "Paramount Comedy"
                    ]
                    if myPrivatePlaylistToNotCacheBecauseStreamURLLifetimeShort.contains(name) == false {
                        self.playlistCache[name] = playlist
                    }

                    DispatchQueue.main.async {
                        present(playlist: playlist)
                    }
                } catch {
                    self.present(error: error)
                    DispatchQueue.main.async {
                        self.setTableViewProgressView(enabled: false)
                    }
                }
            }
        case .providers(let providerKind):
            DispatchQueue.global(qos: .userInitiated).async {
                let provider = self.providers.first(where: { $0.kind.id == providerKind.id })!
                let bundlesIds = self.storage.array(domain: .list(.provider(providerKind.id)))
                let bundles = provider.bundles.filter({ bundlesIds.contains($0.id) })
                let bundlesForSure = bundles.isEmpty ? provider.baseBundles : bundles
                let fav = provider.favChannels.map(\.id)
                let channels: [Channel] = bundlesForSure.flatMap({ $0.playlist.channels })
                let favChannels: [Channel] = fav.compactMap({ f in channels.first(where: { $0.id == f }) })
                let remainsChannels: [Channel] = channels.filter({ !fav.contains($0.id) })
                let playlist = PlaylistItem(channels: favChannels + remainsChannels)
                DispatchQueue.main.async {
                    let playlistVC = PlaylistViewController.instantiate()
                    playlistVC.playlist = playlist
                    playlistVC.programmes = IpTvProgrammesProviders.make(for: provider.kind)
                    self.present(playlistVC, animated: true)
                }
            }
        case .addPlaylist:
            let vc = AddPlaylistViewController(title: "",
                message: NSLocalizedString(
                    "Add playlist url (required) and its name (optional)", comment: ""),
                preferredStyle: .alert)
            vc.configure { [unowned self] url, name in
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    let message = "url: \(String(describing: url)), name: \(String(describing: name))"
                    os_log(.info, "\(message)")
                    guard let url = url else {
                        return
                    }
                    let name = name ?? url.lastPathComponent
                    
                    do {
                        DispatchQueue.main.async {
                            self.setTableViewProgressView(enabled: true)
                        }
                        let file = try fsManager.download(file: url, name: name)
                        do {
                            if try M3U(data: fsManager.content(of: file)!).parse().isEmpty {
                                let error = NSError(domain: "com.tv.player", code: -1, userInfo: [
                                    NSLocalizedDescriptionKey: NSLocalizedString("No channels found.", comment: "")
                                ])
                                throw error
                            }
                        } catch {
                            try self.fsManager.remove(file: file)
                            throw error
                        }
                    } catch {
                        os_log(.error, "\(error as NSError)")
                        self.present(error: error)
                    }
                    
                    DispatchQueue.main.async {
                        self.setTableViewProgressView(enabled: false)
                    }
                }
            }
            self.present(vc, animated: true)
        case .settings:
            let vc = SettingsViewController.instantiate()
            vc.providers = self.providers
            self.present(vc, animated: true)
        }
    }
    
    private struct PlaylistItem: Playlist { let channels: [Channel] }
}
